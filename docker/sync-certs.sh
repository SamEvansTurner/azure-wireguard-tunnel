#!/bin/bash
# Azure WireGuard Tunnel - Certificate Sync (Container Version)
# Syncs certificates to Azure VM only when they change

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File to store certificate checksums
CHECKSUM_FILE="/tmp/cert_checksums.txt"

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Certificate Sync to Azure VM (Container)      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Validate required environment variables
if [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Error: DOMAIN environment variable not set${NC}"
    exit 1
fi

# Hybrid VM_IP resolution: Environment variable takes precedence, fallback to DNS
if [ -n "$VM_IP" ]; then
    echo -e "${BLUE}Using explicit VM_IP:${NC} $VM_IP"
else
    # Resolve VM IP via DNS using public DNS server (bypasses split DNS)
    echo -e "${YELLOW}VM_IP not set, resolving via public DNS...${NC}"
    
    # Use lookup.${DOMAIN} to resolve (bypasses wildcard, gets specific A record)
    LOOKUP_HOST="lookup.${DOMAIN}"
    echo -e "${BLUE}Resolving:${NC} $LOOKUP_HOST via 1.1.1.1 (Cloudflare DNS)"
    
    # Use nslookup with Cloudflare DNS (1.1.1.1) to bypass split DNS
    # Parse output to extract IP address
    VM_IP=$(nslookup "$LOOKUP_HOST" 1.1.1.1 2>/dev/null | grep -A1 "Name:" | tail -n1 | awk '{print $3}')
    
    # Fallback to alternative parsing if first method fails
    if [ -z "$VM_IP" ] || [ "$VM_IP" = "1.1.1.1" ]; then
        VM_IP=$(nslookup "$LOOKUP_HOST" 1.1.1.1 2>/dev/null | grep "Address:" | tail -n1 | awk '{print $2}' | grep -v "1.1.1.1")
    fi
    
    # Validate we got a valid IP
    if [ -z "$VM_IP" ] || [ "$VM_IP" = "1.1.1.1" ]; then
        echo -e "${RED}❌ Failed to resolve $LOOKUP_HOST via DNS${NC}"
        echo "   Make sure your DNS is configured correctly"
        echo "   Alternatively, set VM_IP environment variable explicitly"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Resolved $LOOKUP_HOST -> $VM_IP${NC}"
fi

# Validate IP format
if ! echo "$VM_IP" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
    echo -e "${RED}❌ Invalid IP address format: $VM_IP${NC}"
    exit 1
fi

# Validate SSH_KEY_PATH
if [ -z "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ Error: SSH_KEY_PATH environment variable not set${NC}"
    exit 1
fi

# Optional: CERTSYNC_USER (defaults to certsync)
CERTSYNC_USER="${CERTSYNC_USER:-certsync}"

echo -e "${BLUE}Target:${NC} $CERTSYNC_USER@$VM_IP"
echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo -e "${BLUE}SSH Key:${NC} $SSH_KEY_PATH"
echo ""

# Certificate directory (mounted volume)
CERT_DIR="/certs"

if [ ! -d "$CERT_DIR" ]; then
    echo -e "${RED}❌ Certificate directory not mounted: $CERT_DIR${NC}"
    exit 1
fi

echo -e "${YELLOW}Looking for certificates in:${NC} $CERT_DIR"

# Find certificate files
CERT_FILE=""
KEY_FILE=""

# Try different naming patterns
for pattern in "$DOMAIN" "$(echo $DOMAIN | sed 's/\*\.//')"; do
    if [ -f "$CERT_DIR/$pattern.crt" ]; then
        CERT_FILE="$CERT_DIR/$pattern.crt"
    elif [ -f "$CERT_DIR/$pattern/fullchain.pem" ]; then
        CERT_FILE="$CERT_DIR/$pattern/fullchain.pem"
    fi
    
    if [ -f "$CERT_DIR/$pattern.key" ]; then
        KEY_FILE="$CERT_DIR/$pattern.key"
    elif [ -f "$CERT_DIR/$pattern/privkey.pem" ]; then
        KEY_FILE="$CERT_DIR/$pattern/privkey.pem"
    fi
done

if [ -z "$CERT_FILE" ] || [ -z "$KEY_FILE" ]; then
    echo -e "${RED}❌ Certificate files not found${NC}"
    echo ""
    echo "Looking for patterns:"
    echo "  - $DOMAIN.crt / $DOMAIN.key"
    echo "  - $(echo $DOMAIN | sed 's/\*\.//')/*.crt / $(echo $DOMAIN | sed 's/\*\.//')/*.key"
    echo "  - $DOMAIN/fullchain.pem / $DOMAIN/privkey.pem"
    echo ""
    echo "In directory: $CERT_DIR"
    echo ""
    echo "Available files:"
    ls -la "$CERT_DIR" 2>/dev/null || echo "  (directory empty or inaccessible)"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Found certificate: $CERT_FILE${NC}"
echo -e "${GREEN}✅ Found private key: $KEY_FILE${NC}"
echo ""

# Verify certificate
echo -e "${YELLOW}Verifying certificate...${NC}"
if ! openssl x509 -in "$CERT_FILE" -noout -text &>/dev/null; then
    echo -e "${RED}❌ Invalid certificate file${NC}"
    exit 1
fi

CERT_SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject | sed 's/subject=//')
CERT_EXPIRY=$(openssl x509 -in "$CERT_FILE" -noout -enddate | sed 's/notAfter=//')

echo -e "${GREEN}✅ Certificate valid${NC}"
echo "   Subject: $CERT_SUBJECT"
echo "   Expires: $CERT_EXPIRY"
echo ""

# Check if certificates have changed
echo -e "${YELLOW}Checking for certificate changes...${NC}"

# Calculate current checksums
CURRENT_CERT_SHA=$(sha256sum "$CERT_FILE" | cut -d' ' -f1)
CURRENT_KEY_SHA=$(sha256sum "$KEY_FILE" | cut -d' ' -f1)

# Read stored checksums if they exist
if [ -f "$CHECKSUM_FILE" ]; then
    STORED_CERT_SHA=$(grep "^CERT:" "$CHECKSUM_FILE" 2>/dev/null | cut -d: -f2)
    STORED_KEY_SHA=$(grep "^KEY:" "$CHECKSUM_FILE" 2>/dev/null | cut -d: -f2)
else
    STORED_CERT_SHA=""
    STORED_KEY_SHA=""
fi

# Compare checksums
if [ "$CURRENT_CERT_SHA" = "$STORED_CERT_SHA" ] && \
   [ "$CURRENT_KEY_SHA" = "$STORED_KEY_SHA" ] && \
   [ -n "$STORED_CERT_SHA" ] && [ -n "$STORED_KEY_SHA" ]; then
    echo -e "${GREEN}✓ Certificates unchanged since last sync${NC}"
    echo "   Skipping upload to Azure VM"
    echo ""
    exit 0
fi

if [ -z "$STORED_CERT_SHA" ]; then
    echo -e "${BLUE}🆕 First run - certificates will be synced${NC}"
else
    echo -e "${BLUE}🔄 Certificate change detected - syncing to Azure${NC}"
fi
echo ""

# Check SSH connectivity
echo -e "${YELLOW}Testing SSH connection...${NC}"

# Test with a simple SCP check (more reliable than SSH command execution)
# Create a tiny test file
TEST_FILE=$(mktemp)
echo "test" > "$TEST_FILE"

# Try to copy test file (will be cleaned up by certsync-processor if successful)
if scp -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$TEST_FILE" $CERTSYNC_USER@$VM_IP:/home/$CERTSYNC_USER/incoming/.connection-test 2>/dev/null; then
    echo -e "${GREEN}✅ SSH/SFTP connection successful${NC}"
    echo "   (Connection tested with SFTP - user has restricted shell access)"
    rm -f "$TEST_FILE"
else
    echo -e "${RED}❌ Cannot connect to VM${NC}"
    echo ""
    echo "   Verify:"
    echo "   - SSH key is mounted at: $SSH_KEY_PATH"
    echo "   - VM_IP is correct: $VM_IP"
    echo "   - User exists on Azure VM: $CERTSYNC_USER"
    echo "   - SSH public key is in /home/$CERTSYNC_USER/.ssh/authorized_keys on Azure VM"
    echo "   - SSH server allows SFTP connections"
    rm -f "$TEST_FILE"
    exit 1
fi
echo ""

# Sync certificates
echo -e "${YELLOW}Syncing certificates to Azure VM...${NC}"

# Create temporary files with consistent naming
TMP_DIR=$(mktemp -d)
cp "$CERT_FILE" "$TMP_DIR/$DOMAIN.crt"
cp "$KEY_FILE" "$TMP_DIR/$DOMAIN.key"

# Copy to VM incoming directory
if scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes "$TMP_DIR/$DOMAIN.crt" "$TMP_DIR/$DOMAIN.key" $CERTSYNC_USER@$VM_IP:/home/$CERTSYNC_USER/incoming/; then
    echo -e "${GREEN}✅ Certificates uploaded successfully${NC}"
else
    echo -e "${RED}❌ Failed to upload certificates${NC}"
    rm -rf "$TMP_DIR"
    exit 1
fi

# Clean up temporary files
rm -rf "$TMP_DIR"

# Store checksums for next comparison
echo "CERT:$CURRENT_CERT_SHA" > "$CHECKSUM_FILE"
echo "KEY:$CURRENT_KEY_SHA" >> "$CHECKSUM_FILE"

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Certificate Sync Complete!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 What happens next:${NC}"
echo ""
echo "1. Systemd on Azure VM detects the new certificates"
echo "2. Certificates are validated automatically"
echo "3. Installed to Caddy's certificate directory"
echo "4. Caddy is reloaded automatically"
echo ""

echo -e "${YELLOW}💡 Tip:${NC} Check Azure VM logs (use your admin SSH key):"
echo "   ${GREEN}ssh your-admin-user@$VM_IP 'sudo journalctl -u certsync-processor -f'${NC}"
echo ""
