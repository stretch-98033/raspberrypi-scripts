#!/bin/bash
# backup_docker_volumes.sh
# Copies Docker volumes and Home Assistant config to USB to reduce SD card wear

# Base destination path
DEST_BASE="/mnt/usb/Volumes"

# Explicit volume -> destination folder mapping
declare -A VOLUME_MAP=(
    ["homebox_homebox-data"]="homebox"
    ["nginx-proxy-manager_npm_data"]="nginx-proxy-manager/data"
    ["nginx-proxy-manager_npm_letsencrypt"]="nginx-proxy-manager/letsencrypt"
    ["portainer_portainer_data"]="portainer"
    ["uptime-kuma_uptime-kuma"]="uptime-kuma"
)

# Backup Docker volumes
for VOL in "${!VOLUME_MAP[@]}"; do
    SRC="/var/lib/docker/volumes/${VOL}/_data/"
    DEST="${DEST_BASE}/${VOLUME_MAP[$VOL]}/"

    if [ -d "$SRC" ]; then
        echo "Backing up $VOL -> $DEST"
        mkdir -p "$DEST"
        rsync -a --no-perms --no-owner --no-group --delete "$SRC" "$DEST"
    else
        echo "Source volume $VOL does not exist at $SRC. Skipping."
    fi
done

# Backup Home Assistant config
HA_SRC="/home/pi/homeassistant/"
HA_DEST="${DEST_BASE}/homeassistant/"

echo "Backing up Home Assistant -> $HA_DEST"
mkdir -p "$HA_DEST"
rsync -a --no-perms --no-owner --no-group "$HA_SRC" "$HA_DEST"

echo "Backup complete: $(date)"
