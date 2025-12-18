#!/bin/bash
set -e

# Entrypoint script for USB Sync Manager Docker container

echo "Starting USB Sync Manager..."

# Ensure config directory exists and is writable
mkdir -p /etc/usb-sync-manager
mkdir -p /etc/usb-sync-manager/logs

# Initialize schedules.json if it doesn't exist
if [ ! -f /etc/usb-sync-manager/schedules.json ]; then
    echo "[]" > /etc/usb-sync-manager/schedules.json
    echo "Created schedules.json"
fi

# Initialize config.json if it doesn't exist
if [ ! -f /etc/usb-sync-manager/config.json ]; then
    cat > /etc/usb-sync-manager/config.json << 'EOF'
{
  "version": "1.0",
  "max_sync_timeout": 3600,
  "log_retention_days": 30
}
EOF
    echo "Created config.json"
fi

# Ensure logs directory has proper permissions
chmod 755 /etc/usb-sync-manager
chmod 755 /etc/usb-sync-manager/logs

echo "Configuration ready."
echo "Starting backend service..."

# Execute the command passed to docker run
exec "$@"
