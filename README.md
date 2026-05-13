# Pi-hole Sidebar Hardware Monitor

Adds Raspberry Pi temperature and dynamic fan speed monitoring to the Pi-hole v6 sidebar.

This customization is designed for Raspberry Pi OS running Pi-hole v6 with the embedded `pihole-FTL` web server, where PHP execution may not be available from the Pi-hole admin directory. Instead of using PHP, this implementation generates a static JSON file locally and refreshes it with a systemd timer.

---

# Features

- Live CPU temperature display in both Fahrenheit and Celsius
- Dynamic fan RPM discovery through Linux hwmon
- Automatic sidebar refresh without page reload
- No PHP required
- Compatible with Pi-hole v6 / `pihole-FTL`
- Safe idempotent reinstall behavior
- Automatic sidebar backup before modification
- Lightweight systemd timer-based architecture
- Built-in install / uninstall / status actions
- Hardened file handling and symlink protection
- Automatic cleanup during uninstall
- Safe replacement of existing injected blocks

---

# Compatibility

Tested on:

- Raspberry Pi OS
- Pi-hole v6
- `pihole-FTL` embedded web server
- Raspberry Pi PWM fan

This implementation avoids PHP and should remain compatible with future Pi-hole v6 installations that do not execute PHP from the admin directory.

---

# Example Sidebar Display

```text
Temp: 123.3°F
Temp: 50.7°C
Fan Speed: 2510 RPM
```

The sidebar text intentionally stays compact.

Detailed sensor labels and paths remain available in the tooltip.

---

# Fan Detection

Fan speed is discovered dynamically from Linux hwmon paths.

Compatible fan sensors exposed through hwmon should be detected automatically if Raspberry Pi OS exposes them under:

```text
/sys/class/hwmon/hwmon*/fan*_input
```

This should support:

- Raspberry Pi PWM fan
- Some PoE / PoE+ HAT fans
- Other compatible hwmon-exposed fan devices

---

# Architecture

This customization has three parts:

1. A local shell script reads hardware status from `/sys`
2. A systemd timer refreshes a JSON file every few seconds
3. Sidebar JavaScript polls the JSON endpoint and updates the display live

The browser reads:

```text
/admin/custom/pi-hwmon.json
```

Generated locally at:

```text
/var/www/html/admin/custom/pi-hwmon.json
```

---

# Files Installed

The installer creates or updates:

```text
/usr/local/bin/pi-hwmon-json
/etc/systemd/system/pi-hwmon-json.service
/etc/systemd/system/pi-hwmon-json.timer
/var/www/html/admin/custom/pi-hwmon.json
```

---

# Files Modified

The installer modifies:

```text
/var/www/html/admin/scripts/lua/sidebar.lp
```

The injected sidebar block is wrapped with:

```html
<!-- BEGIN CUSTOM HWMON -->
...
<!-- END CUSTOM HWMON -->
```

---

# Pi-hole v6 Insertion Marker

Pi-hole v6 currently uses:

```html
<span id="memory"></span>
```

The installer injects the sidebar block immediately after this element.

Older insertion logic using:

```html
<span id="memory"><span>
```

will fail on current Pi-hole v6 builds.

---

# Backups

Before modifying the sidebar, the installer creates a timestamped backup:

```text
/var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS
```

Example:

```text
/var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-20260511-175600
```

Keep this backup until the UI is verified working.

---

# Install

Clone the repository:

```bash
git clone https://github.com/stretch-98033/raspberrypi-scripts.git
cd raspberrypi-scripts/pihole
```

Run the installer:

```bash
sudo ./install-pihole-hwmon-sidebar.sh install
```

Or:

```bash
sudo bash install-pihole-hwmon-sidebar.sh install
```

Quick install:

```bash
git clone https://github.com/stretch-98033/raspberrypi-scripts.git && \
cd raspberrypi-scripts/pihole && \
sudo ./install-pihole-hwmon-sidebar.sh install
```

After installation:

1. Open the Pi-hole admin page
2. Refresh the browser
3. Verify temperature and fan RPM appear in the sidebar

---

# Script Usage

```text
sudo ./install-pihole-hwmon-sidebar.sh install
sudo ./install-pihole-hwmon-sidebar.sh uninstall
sudo ./install-pihole-hwmon-sidebar.sh status
```

Optional environment overrides:

```bash
SIDEBAR_FILE=/path/to/sidebar.lp
SNIPPET_FILE=/path/to/sidebar-custom-snippet.html
TIMER_INTERVAL=15sec
```

Example custom timer interval:

```bash
sudo TIMER_INTERVAL=30sec ./install-pihole-hwmon-sidebar.sh install
```

---

# Status Command

The status action reports:

- Active sidebar path
- JSON output path
- systemd timer state
- Current generated JSON contents

Run:

```bash
sudo ./install-pihole-hwmon-sidebar.sh status
```

Example:

```text
Sidebar: /var/www/html/admin/scripts/lua/sidebar.lp
JSON: /var/www/html/admin/custom/pi-hwmon.json
```

---

# Uninstall

The uninstall action safely removes:

- systemd timer
- systemd service
- JSON generator
- generated JSON file
- injected sidebar block

Run:

```bash
sudo ./install-pihole-hwmon-sidebar.sh uninstall
```

The script intentionally leaves sidebar backups in place.

---

# Idempotent Reinstall Behavior

The installer is designed to be safely re-runnable.

If an existing custom block is detected between:

```html
<!-- BEGIN CUSTOM HWMON -->
```

and:

```html
<!-- END CUSTOM HWMON -->
```

the installer replaces the existing block instead of appending duplicate content.

This is useful after:

- Pi-hole updates
- Sidebar corruption
- Snippet modifications
- Reinstallation

---

# Security / Hardening

The installer includes several safety protections:

- Refuses to overwrite symlinks
- Refuses to remove non-regular files
- Uses atomic JSON generation with temporary files
- Uses strict shell execution flags:

```bash
set -euo pipefail
```

- Validates required commands before execution
- Validates snippet existence and non-empty content
- Uses controlled root-owned file installation

---

# Verify Installation

## 1. Confirm fan visibility in Linux

```bash
for f in /sys/class/hwmon/hwmon*/fan*_input; do
  [ -e "$f" ] || continue
  echo "$f: $(cat "$f") RPM"
done
```

Example output:

```text
/sys/class/hwmon/hwmon1/fan1_input: 2510 RPM
```

If this returns nothing, the OS is not exposing fan RPM sensors through hwmon.

---

## 2. Confirm hwmon device names

```bash
for d in /sys/class/hwmon/hwmon*; do
  [ -e "$d" ] || continue
  echo "$d name: $(cat "$d/name" 2>/dev/null || echo "unknown")"
done
```

Example:

```text
/sys/class/hwmon/hwmon0 name: cpu_thermal
/sys/class/hwmon/hwmon1 name: pwmfan
```

---

## 3. Confirm JSON generation

Run:

```bash
sudo /usr/local/bin/pi-hwmon-json
```

Inspect:

```bash
cat /var/www/html/admin/custom/pi-hwmon.json
```

Example:

```json
{"temperature":{"c":50.7,"f":123.3,"path":"/sys/class/thermal/thermal_zone0/temp"},"fans":[{"label":"pwmfan fan1","rpm":2510,"path":"/sys/class/hwmon/hwmon1/fan1_input"}]}
```

---

## 4. Confirm JSON endpoint

```bash
curl http://localhost/admin/custom/pi-hwmon.json
```

Output should match the JSON file.

---

## 5. Confirm timer status

```bash
systemctl status pi-hwmon-json.timer --no-pager
```

Expected:

```text
Active: active (waiting)
```

---

## 6. Confirm service success

```bash
systemctl status pi-hwmon-json.service --no-pager
```

Expected:

```text
status=0/SUCCESS
```

It is normal for the service to show:

```text
Active: inactive (dead)
```

This is a `Type=oneshot` service.

---

## 7. Confirm JSON refresh activity

```bash
stat /var/www/html/admin/custom/pi-hwmon.json
```

The `Modify` timestamp should update repeatedly.

---

## 8. Confirm sidebar injection

```bash
sudo grep -n "BEGIN CUSTOM HWMON\|pi-hwmon.json\|Fan Speed\|END CUSTOM HWMON" /var/www/html/admin/scripts/lua/sidebar.lp
```

---

# Browser Verification

Open the Pi-hole admin UI.

Expected sidebar:

```text
Temp: 123.3°F
Temp: 50.7°C
Fan Speed: 2510 RPM
```

Tooltip example:

```text
pwmfan fan1: /sys/class/hwmon/hwmon1/fan1_input
```

---

# Troubleshooting

## Sidebar stays on `Loading...`

Common symptom:

```text
Temp: Loading...
Fan Speed: Loading...
```

First verify the JSON endpoint:

```bash
curl http://localhost/admin/custom/pi-hwmon.json
```

If the JSON works, inspect browser JavaScript errors:

1. Right-click the page
2. Select **Inspect**
3. Open the **Console**
4. Refresh the page

Common error:

```text
Uncaught SyntaxError: Invalid or unexpected token
```

Inspect the injected sidebar block:

```bash
sudo sed -n '/BEGIN CUSTOM HWMON/,/END CUSTOM HWMON/p' /var/www/html/admin/scripts/lua/sidebar.lp
```

---

## Malformed snippet file

A corrupted snippet file can inject broken JavaScript into `sidebar.lp`.

Validate the snippet:

```bash
grep -nE '<script>|</script>|BEGIN CUSTOM HWMON|END CUSTOM HWMON' sidebar-custom-snippet.html
```

If HTML appears inside JavaScript function bodies, replace the snippet with a clean repository copy.

---

## Browser cache prevents updates

Pi-hole may return aggressive cache headers.

The sidebar JavaScript avoids stale cache using:

```javascript
fetch(ENDPOINT + "?t=" + Date.now(), {
  cache: "no-store"
});
```

---

## PHP endpoint does not execute

Pi-hole v6 may serve PHP source directly instead of executing it.

Test example:

```bash
curl -i http://localhost/admin/scripts/pi-hwmon-test.php
```

If raw PHP source appears, PHP execution is unavailable.

This implementation intentionally avoids PHP entirely.

---

## No fans detected

Run:

```bash
for f in /sys/class/hwmon/hwmon*/fan*_input; do
  [ -e "$f" ] || continue
  echo "$f: $(cat "$f") RPM"
done
```

If no output appears, Linux is not exposing fan RPM sensors through hwmon.

---

# Reapply After Pi-hole Updates

Pi-hole updates may overwrite:

```text
/var/www/html/admin/scripts/lua/sidebar.lp
```

Re-run the installer:

```bash
cd raspberrypi-scripts/pihole
sudo ./install-pihole-hwmon-sidebar.sh install
```

Verify:

```bash
sudo ./install-pihole-hwmon-sidebar.sh status
curl http://localhost/admin/custom/pi-hwmon.json
```

Refresh the browser.

---

# Rollback / Recovery

## Restore sidebar backup

List backups:

```bash
ls -l /var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-*
```

Restore:

```bash
sudo cp /var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS /var/www/html/admin/scripts/lua/sidebar.lp
```

---

## Remove only the custom block

```bash
sudo ./install-pihole-hwmon-sidebar.sh uninstall
```

Or manually edit:

```bash
sudo nano /var/www/html/admin/scripts/lua/sidebar.lp
```

Delete everything between:

```html
<!-- BEGIN CUSTOM HWMON -->
```

and:

```html
<!-- END CUSTOM HWMON -->
```

---

# Hardware Paths Used

Temperature:

```text
/sys/class/thermal/thermal_zone0/temp
```

Fan RPM:

```text
/sys/class/hwmon/hwmon*/fan*_input
```

Fan labels:

```text
/sys/class/hwmon/hwmon*/fan*_label
```

Hwmon device names:

```text
/sys/class/hwmon/hwmon*/name
```

---

# Web Paths

Generated JSON:

```text
/var/www/html/admin/custom/pi-hwmon.json
```

Browser endpoint:

```text
/admin/custom/pi-hwmon.json
```

Pi-hole sidebar:

```text
/var/www/html/admin/scripts/lua/sidebar.lp
```

---

# Notes

- The systemd service intentionally uses `Type=oneshot`
- The timer refreshes the JSON repeatedly
- The browser polls the JSON endpoint every few seconds
- The browser endpoint is read-only
- No PHP or CGI execution is required
- The customization only reads sensor data
- Re-running the installer after Pi-hole updates should restore the customization
- Uninstall safely removes installed components without deleting sidebar backups
- Existing custom blocks are replaced automatically during reinstall
- The installer supports alternate Pi-hole admin paths via `SIDEBAR_FILE`
