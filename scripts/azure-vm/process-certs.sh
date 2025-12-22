#!/bin/bash
# Process uploaded certificates for Caddy
# This script is deployed to /usr/local/bin/process-certs.sh on Azure VM

set -e

INCOMING_DIR="/home/certsync/incoming"
CERT_DIR="/etc/caddy/certs"
DOMAIN="${domain_name}"
LOG_TAG="certsync"

logger -t "$LOG_TAG" "Certificate processing started"

# Check if certificates exist in incoming directory
if [ ! -f "$INCOMING_DIR/$DOMAIN.crt" ] || [ ! -f "$INCOMING_DIR/$DOMAIN.key" ]; then
    logger -t "$LOG_TAG" "No certificates found in incoming directory"
    exit 0
fi

logger -t "$LOG_TAG" "Found certificates: $DOMAIN.crt and $DOMAIN.key"

# Validate certificate
if ! openssl x509 -in "$INCOMING_DIR/$DOMAIN.crt" -noout -text &>/dev/null; then
    logger -t "$LOG_TAG" "ERROR: Invalid certificate file"
    rm -f "$INCOMING_DIR/$DOMAIN.crt" "$INCOMING_DIR/$DOMAIN.key"
    exit 1
fi

# Validate private key
if ! openssl rsa -in "$INCOMING_DIR/$DOMAIN.key" -check -noout &>/dev/null 2>&1 && \
   ! openssl ec -in "$INCOMING_DIR/$DOMAIN.key" -check -noout &>/dev/null 2>&1; then
    logger -t "$LOG_TAG" "ERROR: Invalid private key file"
    rm -f "$INCOMING_DIR/$DOMAIN.crt" "$INCOMING_DIR/$DOMAIN.key"
    exit 1
fi

# Get certificate details
CERT_SUBJECT=$(openssl x509 -in "$INCOMING_DIR/$DOMAIN.crt" -noout -subject 2>/dev/null || echo "Unknown")
CERT_EXPIRY=$(openssl x509 -in "$INCOMING_DIR/$DOMAIN.crt" -noout -enddate 2>/dev/null || echo "Unknown")

logger -t "$LOG_TAG" "Certificate validation passed"
logger -t "$LOG_TAG" "Subject: $CERT_SUBJECT"
logger -t "$LOG_TAG" "Expires: $CERT_EXPIRY"

# Backup existing certificates if they exist
if [ -f "$CERT_DIR/$DOMAIN.crt" ]; then
    BACKUP_DIR="$CERT_DIR/backup"
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    cp "$CERT_DIR/$DOMAIN.crt" "$BACKUP_DIR/$DOMAIN.crt.$TIMESTAMP"
    cp "$CERT_DIR/$DOMAIN.key" "$BACKUP_DIR/$DOMAIN.key.$TIMESTAMP"
    logger -t "$LOG_TAG" "Backed up existing certificates to $BACKUP_DIR"
    
    # Keep only last 5 backups
    ls -t "$BACKUP_DIR/$DOMAIN.crt".* 2>/dev/null | tail -n +6 | xargs -r rm --
    ls -t "$BACKUP_DIR/$DOMAIN.key".* 2>/dev/null | tail -n +6 | xargs -r rm --
fi

# Install certificates
mv "$INCOMING_DIR/$DOMAIN.crt" "$CERT_DIR/"
mv "$INCOMING_DIR/$DOMAIN.key" "$CERT_DIR/"

# Set correct ownership and permissions (caddy user needs to read these)
chown caddy:caddy "$CERT_DIR/$DOMAIN.crt" "$CERT_DIR/$DOMAIN.key"
chmod 644 "$CERT_DIR/$DOMAIN.crt"
chmod 600 "$CERT_DIR/$DOMAIN.key"

logger -t "$LOG_TAG" "Certificates installed successfully"

# Reload Caddy if running
if systemctl is-active --quiet caddy; then
    logger -t "$LOG_TAG" "Reloading Caddy..."
    if systemctl reload caddy; then
        logger -t "$LOG_TAG" "Caddy reloaded successfully"
    else
        logger -t "$LOG_TAG" "ERROR: Failed to reload Caddy"
        exit 1
    fi
else
    logger -t "$LOG_TAG" "Caddy is not running, skipping reload"
fi

# Clean up incoming directory
rm -f "$INCOMING_DIR"/*
logger -t "$LOG_TAG" "Certificate processing complete"
