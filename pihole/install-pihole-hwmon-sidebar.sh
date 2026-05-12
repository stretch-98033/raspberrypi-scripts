#!/bin/bash
set -euo pipefail

SIDEBAR_FILE="/var/www/html/admin/scripts/lua/sidebar.lp"
CUSTOM_DIR="/var/www/html/admin/custom"
JSON_FILE="${CUSTOM_DIR}/pi-hwmon.json"
GENERATOR="/usr/local/bin/pi-hwmon-json"
SERVICE_FILE="/etc/systemd/system/pi-hwmon-json.service"
TIMER_FILE="/etc/systemd/system/pi-hwmon-json.timer"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNIPPET_FILE="${SCRIPT_DIR}/sidebar-custom-snippet.html"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="${SIDEBAR_FILE}.backup-before-hwmon-${TIMESTAMP}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Run this script with sudo."
  exit 1
fi

if [ ! -f "$SIDEBAR_FILE" ]; then
  echo "ERROR: Pi-hole sidebar file not found:"
  echo "$SIDEBAR_FILE"
  exit 1
fi

if [ ! -f "$SNIPPET_FILE" ]; then
  echo "ERROR: Sidebar snippet not found:"
  echo "$SNIPPET_FILE"
  exit 1
fi

echo "Creating custom web directory..."
mkdir -p "$CUSTOM_DIR"

echo "Installing hardware JSON generator..."
cat > "$GENERATOR" <<'EOF'
#!/bin/bash
set -eu

OUT="/var/www/html/admin/custom/pi-hwmon.json"
TMP="${OUT}.tmp"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

read_trimmed() {
  local path="$1"

  if [ -r "$path" ]; then
    tr -d '\n\r' < "$path"
  fi
}

temp_path="/sys/class/thermal/thermal_zone0/temp"
temp_raw="$(read_trimmed "$temp_path" || true)"

temp_c="null"
temp_f="null"

if [ -n "$temp_raw" ] && [ "$temp_raw" -eq "$temp_raw" ] 2>/dev/null; then
  temp_c="$(awk "BEGIN { printf \"%.1f\", $temp_raw / 1000 }")"
  temp_f="$(awk "BEGIN { printf \"%.1f\", ($temp_raw / 1000) * 9 / 5 + 32 }")"
fi

{
  printf '{'
  printf '"temperature":{'
  printf '"c":%s,' "$temp_c"
  printf '"f":%s,' "$temp_f"
  printf '"path":"%s"' "$(json_escape "$temp_path")"
  printf '},'
  printf '"fans":['

  first=1

  for fan_path in /sys/class/hwmon/hwmon*/fan*_input; do
    [ -e "$fan_path" ] || continue

    rpm="$(read_trimmed "$fan_path" || true)"

    case "$rpm" in
      ''|*[!0-9]*)
        continue
        ;;
    esac

    fan_file="$(basename "$fan_path")"
    fan_num="${fan_file#fan}"
    fan_num="${fan_num%_input}"
    hwmon_dir="$(dirname "$fan_path")"

    label="$(read_trimmed "$hwmon_dir/fan${fan_num}_label" || true)"

    if [ -z "$label" ]; then
      hwmon_name="$(read_trimmed "$hwmon_dir/name" || true)"

      if [ -n "$hwmon_name" ]; then
        label="${hwmon_name} fan${fan_num}"
      else
        label="Fan ${fan_num}"
      fi
    fi

    if [ "$first" -eq 0 ]; then
      printf ','
    fi

    first=0

    printf '{'
    printf '"label":"%s",' "$(json_escape "$label")"
    printf '"rpm":%s,' "$rpm"
    printf '"path":"%s"' "$(json_escape "$fan_path")"
    printf '}'
  done

  printf ']'
  printf '}'
} > "$TMP"

mv "$TMP" "$OUT"
chmod 0644 "$OUT"
EOF

chmod +x "$GENERATOR"

echo "Installing systemd service..."
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=Generate Pi hardware monitor JSON

[Service]
Type=oneshot
ExecStart=/usr/local/bin/pi-hwmon-json
EOF

echo "Installing systemd timer..."
cat > "$TIMER_FILE" <<'EOF'
[Unit]
Description=Refresh Pi hardware monitor JSON

[Timer]
OnBootSec=15sec
OnUnitActiveSec=5sec
Unit=pi-hwmon-json.service

[Install]
WantedBy=timers.target
EOF

echo "Backing up sidebar..."
cp "$SIDEBAR_FILE" "$BACKUP_FILE"
echo "Backup created: $BACKUP_FILE"

echo "Injecting sidebar snippet..."

python3 - "$SIDEBAR_FILE" "$SNIPPET_FILE" <<'PY'
import sys
from pathlib import Path

sidebar_path = Path(sys.argv[1])
snippet_path = Path(sys.argv[2])

sidebar = sidebar_path.read_text()
snippet = snippet_path.read_text().strip() + "\n"

begin = "<!-- BEGIN CUSTOM HWMON -->"
end = "<!-- END CUSTOM HWMON -->"

if begin not in snippet or end not in snippet:
    raise SystemExit("ERROR: Snippet must contain BEGIN CUSTOM HWMON and END CUSTOM HWMON markers.")

if begin in sidebar and end in sidebar:
    start = sidebar.index(begin)
    finish = sidebar.index(end, start) + len(end)
    sidebar = sidebar[:start] + snippet.rstrip() + sidebar[finish:]
else:
    old_begin = '<span id="temperatureF">'
    old_end = '<!-- END CUSTOM TEMP -->'

    if old_begin in sidebar and old_end in sidebar:
        start = sidebar.index(old_begin)
        finish = sidebar.index(old_end, start) + len(old_end)
        sidebar = sidebar[:start] + snippet.rstrip() + sidebar[finish:]
    else:
        marker = '<span id="memory"><span>'
        if marker not in sidebar:
            raise SystemExit("ERROR: Could not find existing custom block or insertion marker in sidebar.lp.")

        insert_at = sidebar.index(marker) + len(marker)
        sidebar = sidebar[:insert_at] + "\n" + snippet.rstrip() + "\n" + sidebar[insert_at:]

sidebar_path.write_text(sidebar)
PY

chmod 0644 "$SIDEBAR_FILE"

echo "Generating initial JSON..."
"$GENERATOR"

echo "Reloading systemd..."
systemctl daemon-reload

echo "Enabling and starting timer..."
systemctl enable --now pi-hwmon-json.timer

echo
echo "Install complete."
echo
echo "Verify with:"
echo "  systemctl status pi-hwmon-json.timer --no-pager"
echo "  cat $JSON_FILE"
echo "  curl http://localhost/admin/custom/pi-hwmon.json"
echo
echo "Refresh the Pi-hole admin page to confirm the sidebar display."
