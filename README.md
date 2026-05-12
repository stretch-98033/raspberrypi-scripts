# Pi-hole Sidebar Hardware Monitor

Adds Raspberry Pi temperature and dynamic fan speed display to the Pi-hole sidebar.

## What it does

- Displays CPU temperature in Fahrenheit and Celsius.
- Displays current fan speed as RPM.
- Dynamically discovers fans from `/sys/class/hwmon/hwmon*/fan*_input`.
- Supports future fans such as PoE / PoE+ HAT fans if exposed by Raspberry Pi OS.
- Updates the browser display without refreshing the page.
- Avoids PHP/CGI execution by serving a static JSON file refreshed by systemd.

## Files installed

- `/usr/local/bin/pi-hwmon-json`
- `/etc/systemd/system/pi-hwmon-json.service`
- `/etc/systemd/system/pi-hwmon-json.timer`
- `/var/www/html/admin/custom/pi-hwmon.json`

## Files modified

- `/var/www/html/admin/scripts/lua/sidebar.lp`

## Backups created

- `/var/www/html/admin/scripts/lua/sidebar.lp.backup-before-hwmon-YYYYMMDD-HHMMSS`

## Install

```bash
sudo bash install-pihole-hwmon-sidebar.sh

##Verify
systemctl status pi-hwmon-json.timer --no-pager
cat /var/www/html/admin/custom/pi-hwmon.json

