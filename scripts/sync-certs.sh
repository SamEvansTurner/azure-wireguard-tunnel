#!/bin/bash
# Azure WireGuard Secure Tunnel - Certificate Sync Script
# Syncs Let's Encrypt certificates from home to Azure VM

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        Certificate Sync to Azure VM               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running from project root
if [ ! -d "terraform" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    exit 1
fi

cd terraform

# Get Terraform outputs
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ Terraform state not found. Deploy infrastructure first.${NC}"
    exit 1
fi

VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null)
ADMIN_USER=$(terraform output -raw admin_username 2>/dev/null || grep "^admin_username" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
DOMAIN=$(terraform output -raw domain_name 2>/dev/null || grep "^domain_name" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

cd ..

if [ -z "$VM_IP" ] || [ -z "$ADMIN_USER" ] || [ -z "$DOMAIN" ]; then
    echo -e "${RED}❌ Failed to get deployment information${NC}"
    exit 1
fi

echo -e "${BLUE}Target:${NC} $ADMIN_USER@$VM_IP"
echo -e "${BLUE}Domain:${NC} $DOMAIN"
echo ""

# Default certificate paths (adjust if needed)
CERT_DIR="$HOME/certbot-desec/certs"

# Allow override via environment variable or argument
if [ -n "$1" ]; then
    CERT_DIR="$1"
elif [ -n "$CERT_PATH" ]; then
    CERT_DIR="$CERT_PATH"
fi

echo -e "${YELLOW}Looking for certificates in:${NC} $CERT_DIR"

# Check if certificate directory exists
if [ ! -d "$CERT_DIR" ]; then
    echo -e "${RED}❌ Certificate directory not found: $CERT_DIR${NC}"
    echo ""
    echo "Usage:"
    echo "  $0 [cert-directory]"
    echo ""
    echo "Example:"
    echo "  $0 ~/certbot-desec/certs"
    echo "  $0 /etc/letsencrypt/live/$DOMAIN"
    echo ""
    exit 1
fi

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
    echo "  - $(echo $DOMAIN | sed 's/\*\.//')

.crt / $(echo $DOMAIN | sed 's/\*\.//')/*.key"
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

# Check SSH connectivity
echo -e "${YELLOW}Testing SSH connection...${NC}"
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no $ADMIN_USER@$VM_IP "echo 'Connected'" &>/dev/null; then
    echo -e "${RED}❌ Cannot connect to VM${NC}"
    echo "   Try: ssh $ADMIN_USER@$VM_IP"
    exit 1
fi
echo -e "${GREEN}✅ SSH connection successful${NC}"
echo ""

# Sync certificates
echo -e "${YELLOW}Syncing certificates to Azure VM...${NC}"

# Create temporary files with consistent naming
TMP_DIR=$(mktemp -d)
cp "$CERT_FILE" "$TMP_DIR/$DOMAIN.crt"
cp "$KEY_FILE" "$TMP_DIR/$DOMAIN.key"

# Copy to VM
scp -o StrictHostKeyChecking=no "$TMP_DIR/$DOMAIN.crt" "$TMP_DIR/$DOMAIN.key" $ADMIN_USER@$VM_IP:/tmp/

# Move to correct location and set permissions
ssh $ADMIN_USER@$VM_IP << 'EOF'
sudo mkdir -p /home/'$ADMIN_USER'/certs
sudo mv /tmp/'$DOMAIN'.crt /home/'$ADMIN_USER'/certs/
sudo mv /tmp/'$DOMAIN'.key /home/'$ADMIN_USER'/certs/
sudo chown '$ADMIN_USER':'$ADMIN_USER' /home/'$ADMIN_USER'/certs/'$DOMAIN'.*
sudo chmod 644 /home/'$ADMIN_USER'/certs/'$DOMAIN'.crt
sudo chmod 600 /home/'$ADMIN_USER'/certs/'$DOMAIN'.key
EOF

# Clean up temporary files
rm -rf "$TMP_DIR"

echo -e "${GREEN}✅ Certificates synced${NC}"
echo ""

# Reload Caddy
echo -e "${YELLOW}Reloading Caddy...${NC}"
if ssh $ADMIN_USER@$VM_IP "sudo systemctl is-active caddy" &>/dev/null; then
    ssh $ADMIN_USER@$VM_IP "sudo systemctl reload caddy"
    echo -e "${GREEN}✅ Caddy reloaded${NC}"
else
    echo -e "${YELLOW}ℹ️  Caddy not running. Start with: systemctl start caddy${NC}"
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Certificate Sync Complete!              ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${BLUE}📋 Next Steps:${NC}"
echo ""
echo "1. Verify Caddy is running:"
echo "   ${GREEN}ssh $ADMIN_USER@$VM_IP 'sudo systemctl status caddy'${NC}"
echo ""
echo "2. Test HTTPS access:"
echo "   ${GREEN}curl -I https://$DOMAIN${NC}"
echo ""
echo "3. View Caddy logs:"
echo "   ${GREEN}ssh $ADMIN_USER@$VM_IP 'sudo journalctl -u caddy -f'${NC}"
echo ""

echo -e "${YELLOW}💡 Tip:${NC} Set up automatic sync after certificate renewal:"
echo "   Add this script to your certbot renewal hook"
echo ""
