# Pi-hole v6 Hardware Monitor Sidebar

This folder contains a single-Pi installer that restores Raspberry Pi temperature and fan speed readings to the Pi-hole v6 admin sidebar.

## Files

- `install-pihole-hwmon-sidebar.sh` installs, checks, and uninstalls the customization.
- `sidebar-custom-snippet.html` is the sidebar HTML and JavaScript injected into Pi-hole's `sidebar.lp`.

## Supported Targets

The script is intended for Pi-hole v6 on Raspberry Pi OS, Debian, or DietPi systems that use systemd and the Pi-hole v6 Lua admin UI.

Temperature is auto-detected across Raspberry Pi variants. The generator checks, in order:

- `/sys/class/thermal/thermal_zone*/temp` entries with CPU/SOC/Raspberry Pi labels,
- `/sys/class/hwmon/hwmon*/temp*_input` entries with CPU/SOC/Raspberry Pi labels,
- any valid thermal or hwmon temperature sensor,
- `vcgencmd measure_temp` as a fallback when available.

Fan speed uses RPM-capable hwmon sensors at `/sys/class/hwmon/hwmon*/fan*_input`. Some Raspberry Pi fan controllers and cases expose fan control without exposing RPM feedback; those systems will show `Fan Speed: No RPM sensor found`.

It checks these common Pi-hole v6 sidebar locations:

- `/var/www/html/admin/scripts/lua/sidebar.lp`
- `/var/www/admin/scripts/lua/sidebar.lp`

If your install uses a different path, pass it explicitly:

```bash
sudo SIDEBAR_FILE=/path/to/sidebar.lp ./install-pihole-hwmon-sidebar.sh install
```

## Install

From this folder on the Pi:

```bash
chmod +x install-pihole-hwmon-sidebar.sh
sudo ./install-pihole-hwmon-sidebar.sh install
```

The installer:

- backs up `sidebar.lp` before editing it,
- injects the marked hardware monitor block,
- installs `/usr/local/bin/pi-hwmon-json`,
- installs a systemd oneshot service and timer,
- writes hardware readings to `/admin/custom/pi-hwmon.json`.

## Verify

```bash
sudo ./install-pihole-hwmon-sidebar.sh status
systemctl status pi-hwmon-json.timer --no-pager
curl http://localhost/admin/custom/pi-hwmon.json
```

The JSON includes the detected Pi model, selected temperature source, and any RPM-capable fan sensors. Hover over the sidebar temperature icon to see the selected source path.

Refresh the Pi-hole admin page after install.

## Duplicate Sidebar Rows

If the sidebar shows one live set of temperature and fan readings followed by another set stuck on `Loading...`, `sidebar.lp` contains duplicate custom hardware monitor markup. The live JavaScript updates the first matching element IDs, leaving the duplicate rows unchanged.

Run the installer again to clean up the sidebar:

```bash
sudo ./install-pihole-hwmon-sidebar.sh install
```

The installer removes existing marked hardware monitor blocks and older legacy temp blocks before inserting a single fresh copy.

## Uninstall

```bash
sudo ./install-pihole-hwmon-sidebar.sh uninstall
```

Uninstall disables and removes the timer/service/generator, removes the generated JSON file when the Pi-hole sidebar path can be found, and removes the marked hardware monitor block from `sidebar.lp`.

Backups are left next to `sidebar.lp`.

## Notes

Pi-hole updates can overwrite `sidebar.lp`. If the sidebar customization disappears after an update, rerun the installer.

The sidebar keeps Fahrenheit and Celsius on separate rows to fit the narrow Pi-hole sidebar.
