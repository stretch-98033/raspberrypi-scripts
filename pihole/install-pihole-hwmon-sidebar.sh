#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-install}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET_FILE="${SNIPPET_FILE:-${SCRIPT_DIR}/sidebar-custom-snippet.html}"
GENERATOR="/usr/local/bin/pi-hwmon-json"
SERVICE_FILE="/etc/systemd/system/pi-hwmon-json.service"
TIMER_FILE="/etc/systemd/system/pi-hwmon-json.timer"
TIMER_INTERVAL="${TIMER_INTERVAL:-15sec}"
FETCH_PATH="/admin/custom/pi-hwmon.json"

SIDEBAR_CANDIDATES=(
  "/var/www/html/admin/scripts/lua/sidebar.lp"
  "/var/www/admin/scripts/lua/sidebar.lp"
)

die() {
  echo "ERROR: $*" >&2
  exit 1
}

info() {
  echo "-- $*"
}

usage() {
  cat <<'EOF'
Usage:
  sudo ./install-pihole-hwmon-sidebar.sh install
  sudo ./install-pihole-hwmon-sidebar.sh uninstall
  sudo ./install-pihole-hwmon-sidebar.sh status

Optional environment overrides:
  SIDEBAR_FILE=/path/to/sidebar.lp
  SNIPPET_FILE=/path/to/sidebar-custom-snippet.html
  TIMER_INTERVAL=15sec

This targets Pi-hole v6's Lua admin sidebar and publishes hardware readings at:
  /admin/custom/pi-hwmon.json
EOF
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Run this script with sudo."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

resolve_sidebar_file() {
  if [ -n "${SIDEBAR_FILE:-}" ]; then
    [ -f "$SIDEBAR_FILE" ] || die "SIDEBAR_FILE does not exist: $SIDEBAR_FILE"
    printf '%s\n' "$SIDEBAR_FILE"
    return
  fi

  local candidate
  for candidate in "${SIDEBAR_CANDIDATES[@]}"; do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  die "Pi-hole v6 sidebar.lp not found. Set SIDEBAR_FILE=/path/to/sidebar.lp and run again."
}

reject_symlink() {
  local path="$1"

  if [ -L "$path" ]; then
    die "Refusing to overwrite symlink: $path"
  fi
}

safe_remove_if_regular() {
  local path="$1"

  if [ -e "$path" ] || [ -L "$path" ]; then
    reject_symlink "$path"
    [ -f "$path" ] || die "Refusing to remove non-regular file: $path"
    rm -f "$path"
  fi
}

preflight_common() {
  require_root
  require_command python3
  require_command systemctl
  require_command install
  require_command mktemp
}

preflight_install() {
  preflight_common
  require_command dirname
  require_command basename

  [ -f "$SNIPPET_FILE" ] || die "Sidebar snippet not found: $SNIPPET_FILE"
  [ -s "$SNIPPET_FILE" ] || die "Sidebar snippet is empty: $SNIPPET_FILE"

  reject_symlink "$GENERATOR"
  reject_symlink "$SERVICE_FILE"
  reject_symlink "$TIMER_FILE"
}

write_root_file() {
  local target="$1"
  local mode="$2"
  local tmp

  tmp="$(mktemp)"
  cat > "$tmp"
  install -o root -g root -m "$mode" "$tmp" "$target"
  rm -f "$tmp"
}

install_generator() {
  local json_file="$1"

  info "Installing hardware JSON generator at $GENERATOR"
  write_root_file "$GENERATOR" 0755 <<EOF
#!/usr/bin/env bash
set -euo pipefail

OUT="$json_file"
OUT_DIR="\$(dirname "\$OUT")"
TMP="\$(mktemp "\${OUT_DIR}/.pi-hwmon.json.XXXXXX")"

cleanup() {
  rm -f "\$TMP"
}
trap cleanup EXIT

python3 - "\$TMP" <<'PY'
import glob
import json
import os
import re
import subprocess
import sys
from pathlib import Path

out_path = Path(sys.argv[1])

PI_TEMP_KEYWORDS = (
    "cpu",
    "soc",
    "bcm",
    "bcm2835",
    "rpi",
    "raspberry",
)


def read_trimmed(path):
    try:
        return Path(path).read_text(encoding="utf-8", errors="replace").strip()
    except OSError:
        return ""


def parse_millidegree(raw):
    if not raw:
        return None

    raw = raw.strip()
    try:
        value = float(raw)
    except ValueError:
        return None

    if value > 1000:
        value = value / 1000

    if value < -40 or value > 125:
        return None

    return value


def source_priority(label):
    normalized = label.lower()

    for index, keyword in enumerate(PI_TEMP_KEYWORDS):
        if keyword in normalized:
            return index

    return len(PI_TEMP_KEYWORDS)


def append_temperature(candidates, label, path, raw, source_type):
    celsius = parse_millidegree(raw)
    if celsius is None:
        return

    candidates.append({
        "label": label or "Temperature",
        "path": path,
        "source": source_type,
        "c": round(celsius, 1),
        "priority": source_priority(label or path),
    })


def collect_thermal_temperatures():
    candidates = []

    for temp_path in sorted(glob.glob("/sys/class/thermal/thermal_zone*/temp")):
        zone_dir = os.path.dirname(temp_path)
        zone_type = read_trimmed(os.path.join(zone_dir, "type")) or os.path.basename(zone_dir)
        append_temperature(candidates, zone_type, temp_path, read_trimmed(temp_path), "thermal_zone")

    return candidates


def collect_hwmon_temperatures():
    candidates = []

    for temp_path in sorted(glob.glob("/sys/class/hwmon/hwmon*/temp*_input")):
        hwmon_dir = os.path.dirname(temp_path)
        temp_file = os.path.basename(temp_path)
        temp_num = temp_file.removeprefix("temp").removesuffix("_input")
        hwmon_name = read_trimmed(os.path.join(hwmon_dir, "name"))
        temp_label = read_trimmed(os.path.join(hwmon_dir, f"temp{temp_num}_label"))
        label_parts = [part for part in (hwmon_name, temp_label or f"temp{temp_num}") if part]
        label = " ".join(label_parts) if label_parts else f"Temperature {temp_num}"
        append_temperature(candidates, label, temp_path, read_trimmed(temp_path), "hwmon")

    return candidates


def collect_vcgencmd_temperature():
    try:
        result = subprocess.run(
            ["vcgencmd", "measure_temp"],
            check=False,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return []

    if result.returncode != 0:
        return []

    match = re.search(r"temp=([-+]?[0-9]+(?:\.[0-9]+)?)", result.stdout)
    if not match:
        return []

    celsius = parse_millidegree(match.group(1))
    if celsius is None:
        return []

    return [{
        "label": "vcgencmd measure_temp",
        "path": "vcgencmd measure_temp",
        "source": "vcgencmd",
        "c": round(celsius, 1),
        "priority": 0,
    }]


def select_temperature():
    candidates = []
    candidates.extend(collect_thermal_temperatures())
    candidates.extend(collect_hwmon_temperatures())

    if not candidates:
        candidates.extend(collect_vcgencmd_temperature())

    temperature = {
        "c": None,
        "f": None,
        "path": "",
        "label": "",
        "source": "",
    }

    if not candidates:
        return temperature

    selected = sorted(candidates, key=lambda item: (item["priority"], item["source"], item["path"]))[0]
    temperature["c"] = selected["c"]
    temperature["f"] = round((selected["c"] * 9 / 5) + 32, 1)
    temperature["path"] = selected["path"]
    temperature["label"] = selected["label"]
    temperature["source"] = selected["source"]

    return temperature


def detect_pi_model():
    model = read_trimmed("/proc/device-tree/model").rstrip("\x00")
    if model:
        return model

    for line in read_trimmed("/proc/cpuinfo").splitlines():
        if line.lower().startswith("model"):
            parts = line.split(":", 1)
            if len(parts) == 2:
                return parts[1].strip()

    return ""


temperature = {
    "c": None,
    "f": None,
    "path": "",
    "label": "",
    "source": "",
}
temperature = select_temperature()

fans = []
for fan_path in sorted(glob.glob("/sys/class/hwmon/hwmon*/fan*_input")):
    rpm_raw = read_trimmed(fan_path)
    if not rpm_raw.isdigit():
        continue

    rpm = int(rpm_raw)
    fan_file = os.path.basename(fan_path)
    fan_num = fan_file.removeprefix("fan").removesuffix("_input")
    hwmon_dir = os.path.dirname(fan_path)
    hwmon_name = read_trimmed(os.path.join(hwmon_dir, "name"))
    label = read_trimmed(os.path.join(hwmon_dir, f"fan{fan_num}_label"))

    if not label:
        label = f"{hwmon_name} fan{fan_num}" if hwmon_name else f"Fan {fan_num}"

    fans.append({
        "label": label,
        "rpm": rpm,
        "path": fan_path,
        "source": hwmon_name or "hwmon",
    })

payload = {
    "model": detect_pi_model(),
    "temperature": temperature,
    "fans": fans,
}

out_path.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
PY

install -o root -g root -m 0644 "\$TMP" "\$OUT"
trap - EXIT
rm -f "\$TMP"
EOF
}

install_systemd_units() {
  info "Installing systemd service and timer"

  write_root_file "$SERVICE_FILE" 0644 <<EOF
[Unit]
Description=Generate Pi hardware monitor JSON

[Service]
Type=oneshot
ExecStart=$GENERATOR
EOF

  write_root_file "$TIMER_FILE" 0644 <<EOF
[Unit]
Description=Refresh Pi hardware monitor JSON

[Timer]
OnBootSec=15sec
OnUnitActiveSec=$TIMER_INTERVAL
Unit=pi-hwmon-json.service

[Install]
WantedBy=timers.target
EOF
}

inject_sidebar_snippet() {
  local sidebar_file="$1"
  local backup_file="$2"

  info "Backing up sidebar to $backup_file"
  cp -p "$sidebar_file" "$backup_file"

  info "Injecting hardware monitor snippet"
  python3 - "$sidebar_file" "$SNIPPET_FILE" <<'PY'
import sys
from pathlib import Path

sidebar_path = Path(sys.argv[1])
snippet_path = Path(sys.argv[2])

sidebar = sidebar_path.read_text(encoding="utf-8", errors="replace")
snippet = snippet_path.read_text(encoding="utf-8", errors="replace").strip() + "\n"

begin = "<!-- BEGIN CUSTOM HWMON -->"
end = "<!-- END CUSTOM HWMON -->"

if begin not in snippet or end not in snippet:
    raise SystemExit("ERROR: Snippet must contain BEGIN CUSTOM HWMON and END CUSTOM HWMON markers.")

def remove_marked_blocks(text, block_begin, block_end):
    removed = 0

    while block_begin in text and block_end in text:
        start = text.index(block_begin)
        finish = text.index(block_end, start) + len(block_end)
        text = text[:start].rstrip() + "\n" + text[finish:].lstrip("\n")
        removed += 1

    if block_begin in text or block_end in text:
        raise SystemExit("ERROR: Found an incomplete custom hardware monitor block in sidebar.lp.")

    return text, removed

def remove_legacy_block(text):
    old_begin = '<span id="temperatureF">'
    old_end = '<!-- END CUSTOM TEMP -->'
    removed = 0

    while old_begin in text and old_end in text:
        start = text.index(old_begin)
        finish = text.index(old_end, start) + len(old_end)
        text = text[:start].rstrip() + "\n" + text[finish:].lstrip("\n")
        removed += 1

    if old_begin in text or old_end in text:
        raise SystemExit("ERROR: Found an incomplete legacy custom temperature block in sidebar.lp.")

    return text, removed

sidebar, removed_hwmon = remove_marked_blocks(sidebar, begin, end)
sidebar, removed_legacy = remove_legacy_block(sidebar)

marker = '<span id="memory"></span>'
if marker not in sidebar:
    raise SystemExit("ERROR: Could not find insertion marker in sidebar.lp.")

insert_at = sidebar.index(marker) + len(marker)
sidebar = sidebar[:insert_at] + "\n" + snippet.rstrip() + "\n" + sidebar[insert_at:]

if removed_hwmon or removed_legacy:
    print(f"Replaced {removed_hwmon} hardware monitor block(s) and {removed_legacy} legacy block(s).")

sidebar_path.write_text(sidebar, encoding="utf-8")
PY

  chmod 0644 "$sidebar_file"
}

remove_sidebar_snippet() {
  local sidebar_file="$1"

  info "Removing custom hardware monitor block from sidebar"
  python3 - "$sidebar_file" <<'PY'
import sys
from pathlib import Path

sidebar_path = Path(sys.argv[1])
sidebar = sidebar_path.read_text(encoding="utf-8", errors="replace")
begin = "<!-- BEGIN CUSTOM HWMON -->"
end = "<!-- END CUSTOM HWMON -->"

if begin in sidebar and end in sidebar:
    while begin in sidebar and end in sidebar:
        start = sidebar.index(begin)
        finish = sidebar.index(end, start) + len(end)
        sidebar = sidebar[:start].rstrip() + "\n" + sidebar[finish:].lstrip("\n")
    sidebar_path.write_text(sidebar, encoding="utf-8")
else:
    print("No custom hardware monitor block found in sidebar.")
PY
}

install_hwmon() {
  local sidebar_file
  local admin_dir
  local custom_dir
  local json_file
  local timestamp
  local backup_file

  preflight_install
  sidebar_file="$(resolve_sidebar_file)"
  reject_symlink "$sidebar_file"

  admin_dir="$(cd "$(dirname "$sidebar_file")/../.." && pwd)"
  custom_dir="${admin_dir}/custom"
  json_file="${custom_dir}/pi-hwmon.json"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_file="${sidebar_file}.backup-before-hwmon-${timestamp}"

  info "Using Pi-hole admin directory: $admin_dir"
  info "Using sidebar file: $sidebar_file"
  info "Using snippet file: $SNIPPET_FILE"

  mkdir -p "$custom_dir"
  chmod 0755 "$custom_dir"

  install_generator "$json_file"
  install_systemd_units
  inject_sidebar_snippet "$sidebar_file" "$backup_file"

  info "Generating initial JSON"
  "$GENERATOR"

  info "Reloading systemd"
  systemctl daemon-reload

  info "Enabling and starting timer"
  systemctl enable --now pi-hwmon-json.timer

  echo
  echo "Install complete."
  echo
  echo "Verify with:"
  echo "  systemctl status pi-hwmon-json.timer --no-pager"
  echo "  cat $json_file"
  echo "  curl http://localhost${FETCH_PATH}"
  echo
  echo "Refresh the Pi-hole admin page to confirm the sidebar display."
  echo "Pi-hole updates can overwrite sidebar.lp; rerun this installer if the custom block disappears."
}

uninstall_hwmon() {
  local sidebar_file
  local admin_dir
  local json_file

  preflight_common

  info "Stopping and disabling timer if present"
  systemctl disable --now pi-hwmon-json.timer >/dev/null 2>&1 || true

  safe_remove_if_regular "$TIMER_FILE"
  safe_remove_if_regular "$SERVICE_FILE"
  safe_remove_if_regular "$GENERATOR"

  systemctl daemon-reload

  sidebar_file="$(resolve_sidebar_file 2>/dev/null)" || sidebar_file=""
  if [ -n "$sidebar_file" ] && [ -f "$sidebar_file" ]; then
    reject_symlink "$sidebar_file"
    admin_dir="$(cd "$(dirname "$sidebar_file")/../.." && pwd)"
    json_file="${admin_dir}/custom/pi-hwmon.json"
    safe_remove_if_regular "$json_file"
    remove_sidebar_snippet "$sidebar_file"
  else
    echo "Sidebar file not found; skipped sidebar and JSON cleanup."
  fi

  echo
  echo "Uninstall complete."
  echo "Existing sidebar backups were left in place next to sidebar.lp."
}

status_hwmon() {
  local sidebar_file
  local admin_dir
  local json_file

  preflight_common
  sidebar_file="$(resolve_sidebar_file)"
  admin_dir="$(cd "$(dirname "$sidebar_file")/../.." && pwd)"
  json_file="${admin_dir}/custom/pi-hwmon.json"

  echo "Sidebar: $sidebar_file"
  echo "JSON: $json_file"
  echo
  systemctl status pi-hwmon-json.timer --no-pager || true
  echo
  if [ -f "$json_file" ]; then
    cat "$json_file"
  else
    echo "JSON file not found."
  fi
}

case "$ACTION" in
  install)
    install_hwmon
    ;;
  uninstall)
    uninstall_hwmon
    ;;
  status)
    status_hwmon
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    die "Unknown action: $ACTION"
    ;;
esac
