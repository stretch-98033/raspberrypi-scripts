# Pi-hole Sidebar Hardware Monitor

Adds Raspberry Pi temperature and dynamic fan speed display to the Pi-hole sidebar.

This customization is designed for Raspberry Pi OS running Pi-hole v6 / `pihole-FTL`, where PHP may not execute from the Pi-hole admin directory. Instead of using a PHP endpoint, this setup generates a static JSON file on the Pi and refreshes it with a systemd timer.

## What this adds

The Pi-hole sidebar will show:

```text
Temp: 123.3°F
Temp: 50.7°C
Fan Speed: 2510 RPM
```

Fan speed is discovered dynamically from Linux hwmon paths, so future fans should be picked up automatically if Raspberry Pi OS exposes them under:

```text
/sys/class/hwmon/hwmon*/fan*_input
```

This should support the Raspberry Pi PWM fan and may support PoE / PoE+ HAT fans if the OS exposes their fan RPM through hwmon.

## How it works

This customization has three parts:

1. A local script reads hardware status from `/sys`.
2. A systemd timer refreshes a JSON file every few seconds.
3. The Pi-hole sidebar JavaScript reads that JSON file and updates the display without a page refresh.

The browser reads:

```text
/admin/custom/pi-hwmon.json
```

That file is generated locally at:

```text
/var/www/html/admin/custom/pi-hwmon.json
```

## Files installed

The installer creates or updates these files:

```text
/usr/local/bin/pi-hwmon-json
/etc/systemd/system/pi-hwmon-json.service
/etc/systemd/system/pi-hwmon-json.timer
/var/www/html/admin/custom/pi-hwmon.json
```

## Files modified

The installer modifies:

```text
/var/www/html/admin/scripts/lua/sidebar.lp
```

The sidebar customization should be wrapped with these markers:

```html
<!-- BEGIN CUSTOM HWMON -->
...
<!-- END CUSTOM HWMON -->
```

## Backups created

Before modifying the Pi-hole sidebar, the installer should create a timestamped backup:

```text
/var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS
```

Example:

```text
/var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-20260511-175600
```

Keep this backup until you confirm the Pi-hole UI works correctly.

## Install

Clone this repo onto the Pi:

```bash
git clone https://github.com/YOUR-USER/YOUR-REPO.git
cd YOUR-REPO
```

Run the installer:

```bash
sudo bash install-pihole-hwmon-sidebar.sh
```

Then open the Pi-hole admin page and confirm the sidebar shows temperature and fan speed.

## Verify installation

### 1. Confirm the fan is visible to Raspberry Pi OS

```bash
for f in /sys/class/hwmon/hwmon*/fan*_input; do
  [ -e "$f" ] || continue
  echo "$f: $(cat "$f") RPM"
done
```

Expected output should look similar to:

```text
/sys/class/hwmon/hwmon1/fan1_input: 2510 RPM
```

If this command returns nothing, Raspberry Pi OS is not exposing a fan RPM sensor through hwmon.

### 2. Confirm hwmon device names

```bash
for d in /sys/class/hwmon/hwmon*; do
  [ -e "$d" ] || continue
  echo "$d name: $(cat "$d/name" 2>/dev/null || echo "unknown")"
done
```

Example output:

```text
/sys/class/hwmon/hwmon0 name: cpu_thermal
/sys/class/hwmon/hwmon1 name: pwmfan
/sys/class/hwmon/hwmon2 name: rp1_adc
/sys/class/hwmon/hwmon3 name: rpi_volt
```

### 3. Confirm the JSON generator works

Run:

```bash
sudo /usr/local/bin/pi-hwmon-json
```

Then inspect the JSON:

```bash
cat /var/www/html/admin/custom/pi-hwmon.json
```

Expected output:

```json
{"temperature":{"c":50.7,"f":123.3,"path":"/sys/class/thermal/thermal_zone0/temp"},"fans":[{"label":"pwmfan fan1","rpm":2510,"path":"/sys/class/hwmon/hwmon1/fan1_input"}]}
```

RPM and temperature values will vary.

### 4. Confirm the JSON is reachable through the Pi-hole web server

```bash
curl http://localhost/admin/custom/pi-hwmon.json
```

Expected output should match the JSON file:

```json
{"temperature":{"c":50.7,"f":123.3,"path":"/sys/class/thermal/thermal_zone0/temp"},"fans":[{"label":"pwmfan fan1","rpm":2510,"path":"/sys/class/hwmon/hwmon1/fan1_input"}]}
```

### 5. Confirm the systemd timer is active

```bash
systemctl status pi-hwmon-json.timer --no-pager
```

Expected status:

```text
Active: active (waiting)
```

### 6. Confirm the systemd service is succeeding

```bash
systemctl status pi-hwmon-json.service --no-pager
```

Expected result:

```text
status=0/SUCCESS
```

It is normal for the service to show:

```text
Active: inactive (dead)
```

This is a `oneshot` service. It runs, generates the JSON file, exits successfully, and waits for the timer to run it again.

### 7. Confirm the JSON file is being refreshed

```bash
stat /var/www/html/admin/custom/pi-hwmon.json
```

Check the `Modify` timestamp. It should update every few seconds while the timer is active.

### 8. Confirm the sidebar snippet was injected

```bash
sudo grep -n "BEGIN CUSTOM HWMON\|pi-hwmon.json\|Fan Speed\|END CUSTOM HWMON" /var/www/html/admin/scripts/lua/sidebar.lp
```

Expected output should show the custom block and the JSON endpoint.

## Browser verification

Open the Pi-hole admin page.

Expected sidebar display:

```text
Temp: 123.3°F
Temp: 50.7°C
Fan Speed: 2510 RPM
```

The exact values will vary.

The fan tooltip should preserve the sensor detail, such as:

```text
pwmfan fan1: /sys/class/hwmon/hwmon1/fan1_input
```

## Troubleshooting

### Sidebar stays on `Loading...`

Check the JSON file:

```bash
curl http://localhost/admin/custom/pi-hwmon.json
```

If that works, open browser DevTools:

1. Right-click the Pi-hole page.
2. Select **Inspect**.
3. Open the **Console** tab.
4. Refresh the page.
5. Look for JavaScript errors.

Common issue:

```text
Uncaught SyntaxError: Invalid or unexpected token
```

If this happens, inspect the injected sidebar block:

```bash
sudo sed -n '1,220p' /var/www/html/admin/scripts/lua/sidebar.lp
```

Look for broken JavaScript strings, especially around `.join(...)`.

### Fan speed is cut off in the sidebar

The visible fan text should only show RPM:

```text
Fan Speed: 2510 RPM
```

Do not show the full label in the sidebar text if it is too long.

The display line should use logic equivalent to:

```javascript
fanText.innerText = "Fan Speed: " + fans.map(function (fan) {
  return fan.rpm + " RPM";
}).join(" | ");
```

Keep the long label/path in the tooltip instead.

### JSON updates but browser does not update

Pi-hole may return a cache header like:

```text
Cache-Control: max-age=3600
```

The sidebar JavaScript should fetch the JSON with a timestamp query string:

```javascript
fetch(ENDPOINT + "?t=" + Date.now(), {
  cache: "no-store"
});
```

This prevents the browser from using stale cached JSON.

### PHP endpoint does not work

On Pi-hole v6 / `pihole-FTL`, PHP may not execute from the admin directory. A `.php` file may be served as plain text instead of executing.

Test example:

```bash
curl -i http://localhost/admin/scripts/pi-hwmon-test.php
```

If the response shows PHP source code, do not use PHP for this customization.

This repo intentionally avoids PHP and uses a static JSON file refreshed by systemd.

### No fans are detected

Run:

```bash
for f in /sys/class/hwmon/hwmon*/fan*_input; do
  [ -e "$f" ] || continue
  echo "$f: $(cat "$f") RPM"
done
```

If no output appears, the OS is not exposing any fan RPM sensors through hwmon.

This customization can only display fans that Raspberry Pi OS exposes under:

```text
/sys/class/hwmon/hwmon*/fan*_input
```

A PoE / PoE+ HAT fan will only appear if the kernel/firmware exposes its tachometer reading through hwmon.

## Restart or reapply

After a Pi-hole update, the sidebar file may be overwritten.

Re-run:

```bash
cd YOUR-REPO
sudo bash install-pihole-hwmon-sidebar.sh
```

Then verify:

```bash
systemctl status pi-hwmon-json.timer --no-pager
curl http://localhost/admin/custom/pi-hwmon.json
```

Refresh the Pi-hole admin page.

## Rollback

### Option 1: Restore the sidebar backup

Find available backups:

```bash
ls -l /var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-*
```

Restore the desired backup:

```bash
sudo cp /var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS /var/www/html/admin/scripts/lua/sidebar.lp
```

Replace `YYYYMMDD-HHMMSS` with the actual timestamp.

### Option 2: Remove only the custom sidebar block

If the sidebar block is wrapped with markers, remove it manually:

```bash
sudo nano /var/www/html/admin/scripts/lua/sidebar.lp
```

Delete everything from:

```html
<!-- BEGIN CUSTOM HWMON -->
```

through:

```html
<!-- END CUSTOM HWMON -->
```

Save and exit.

### Option 3: Disable the JSON refresh timer

```bash
sudo systemctl disable --now pi-hwmon-json.timer
```

Confirm it stopped:

```bash
systemctl status pi-hwmon-json.timer --no-pager
```

### Option 4: Remove installed files

```bash
sudo rm -f /usr/local/bin/pi-hwmon-json
sudo rm -f /etc/systemd/system/pi-hwmon-json.service
sudo rm -f /etc/systemd/system/pi-hwmon-json.timer
sudo rm -f /var/www/html/admin/custom/pi-hwmon.json
sudo systemctl daemon-reload
```

Optional: remove the custom web directory if it is empty:

```bash
sudo rmdir /var/www/html/admin/custom 2>/dev/null || true
```

## Full clean removal

To fully remove this customization:

```bash
sudo systemctl disable --now pi-hwmon-json.timer
sudo rm -f /usr/local/bin/pi-hwmon-json
sudo rm -f /etc/systemd/system/pi-hwmon-json.service
sudo rm -f /etc/systemd/system/pi-hwmon-json.timer
sudo rm -f /var/www/html/admin/custom/pi-hwmon.json
sudo systemctl daemon-reload
```

Then restore the original sidebar:

```bash
sudo cp /var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS /var/www/html/admin/scripts/lua/sidebar.lp
```

## Files and paths reference

### Hardware paths read by the generator

Temperature:

```text
/sys/class/thermal/thermal_zone0/temp
```

Fan speed:

```text
/sys/class/hwmon/hwmon*/fan*_input
```

Fan labels, if available:

```text
/sys/class/hwmon/hwmon*/fan*_label
```

Hwmon device names:

```text
/sys/class/hwmon/hwmon*/name
```

### Web JSON output

```text
/var/www/html/admin/custom/pi-hwmon.json
```

Browser path:

```text
/admin/custom/pi-hwmon.json
```

### Pi-hole sidebar file

```text
/var/www/html/admin/scripts/lua/sidebar.lp
```

## Notes

- The systemd service is intentionally `Type=oneshot`.
- The timer refreshes the JSON file repeatedly.
- The browser polls the JSON file every few seconds.
- The JSON endpoint is static and read-only from the browser’s perspective.
- No PHP or CGI execution is required.
- The customization does not write to `/sys`; it only reads sensor values.
- Running the installer after a Pi-hole update should restore the customization.
