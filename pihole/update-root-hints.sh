#!/bin/bash

# Define target location
TARGET="/var/lib/unbound/root.hints"
URL="https://www.internic.net/domain/named.cache"

# Download and overwrite
curl -sSL "$URL" -o "$TARGET"

# Fix permissions (replace 'unbound' with your user if different)
chown unbound:unbound "$TARGET"

# Restart unbound (optional)
# systemctl restart unbound
