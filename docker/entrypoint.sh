#!/bin/bash
# Entrypoint for certificate sync container
# Runs sync on a schedule with configurable interval

set -e

# Validate SSH_KEY_PATH is set and exists
if [ -z "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH_KEY_PATH environment variable not set"
    echo "Please set SSH_KEY_PATH to the path of your SSH private key"
    echo "Example: SSH_KEY_PATH=/ssh-key/id_ed25519"
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH key not found at $SSH_KEY_PATH"
    echo "Please ensure the SSH key is mounted to this path"
    exit 1
fi

if [ ! -r "$SSH_KEY_PATH" ]; then
    echo "ERROR: SSH key at $SSH_KEY_PATH is not readable"
    echo "Check file permissions on the host"
    exit 1
fi

echo "✓ SSH key found at $SSH_KEY_PATH"
echo ""

# Get sync interval (default 24 hours)
SYNC_INTERVAL="${SYNC_INTERVAL:-86400}"

echo "Certificate Sync Daemon Started"
echo "Sync interval: $SYNC_INTERVAL seconds ($(($SYNC_INTERVAL / 3600)) hours)"
echo "Press Ctrl+C to stop"
echo ""

# Run sync loop forever
while true; do
    echo "─────────────────────────────────────────────────────"
    echo "Starting sync check at $(date)"
    echo ""
    
    # Run sync script (don't exit on failure)
    if /app/sync-certs.sh; then
        echo ""
        echo "✓ Sync check complete at $(date)"
    else
        echo ""
        echo "⚠ Sync failed, will retry at next interval"
    fi
    
    echo ""
    echo "Sleeping for $SYNC_INTERVAL seconds..."
    echo "Next check at $(date -d "+$SYNC_INTERVAL seconds" 2>/dev/null || date -v+${SYNC_INTERVAL}S 2>/dev/null || echo "in $SYNC_INTERVAL seconds")"
    echo ""
    
    sleep "$SYNC_INTERVAL"
done
