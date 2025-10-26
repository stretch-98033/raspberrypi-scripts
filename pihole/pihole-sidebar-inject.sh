#!/bin/bash
#updated 10.26.2025 at 4:51pm PST
#test push to git

# Paths
SIDEBAR_FILE="/var/www/html/admin/scripts/lua/sidebar.lp"
BACKUP_DIR="/etc/pihole/sidebar-backups"
CUSTOM_SNIPPET="/etc/pihole/sidebar-custom-snippet.lua"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Backup original if not already done
if [ ! -f "$BACKUP_DIR/sidebar.lp.original" ]; then
    cp "$SIDEBAR_FILE" "$BACKUP_DIR/sidebar.lp.original"
fi

# Exit if custom code file is missing
if [ ! -f "$CUSTOM_SNIPPET" ]; then
    echo "Custom snippet file not found at $CUSTOM_SNIPPET"
    exit 1
fi

# Read the custom snippet
CUSTOM_CODE=$(<"$CUSTOM_SNIPPET")

# Remove any previous injected block (between markers)
sed -i '/<!-- BEGIN CUSTOM TEMP -->/,/<!-- END CUSTOM TEMP -->/d' "$SIDEBAR_FILE"

# Inject after the memory span
awk -v code="$CUSTOM_CODE" '
    /<span id="memory">/ { found=1 }
    found && /<\/span>/ {
        print
        print "<!-- BEGIN CUSTOM TEMP -->"
        print code
        print "<!-- END CUSTOM TEMP -->"
        found=0
        next
    }
    { print }
' "$SIDEBAR_FILE" > /tmp/sidebar.lp && mv /tmp/sidebar.lp "$SIDEBAR_FILE"

# Set permissions
chown www-data:www-data "$SIDEBAR_FILE"
chmod 644 "$SIDEBAR_FILE"

echo "Sidebar customization injected successfully."

