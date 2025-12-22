#!/bin/bash
# Azure WireGuard Secure Tunnel - Fast Caddy Config Update
# Updates Caddy configuration on Azure VM without recreating infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Fast Caddy Configuration Update               ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running from project root
if [ ! -d "terraform" ] || [ ! -d "azure-configs" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo -e "${YELLOW}[1/5] Reading configuration template...${NC}"

if [ ! -f "azure-configs/Caddyfile.template" ]; then
    echo -e "${RED}❌ Error: azure-configs/Caddyfile.template not found${NC}"
    echo "Run ./scripts/deploy-azure.sh first to set up configs"
    exit 1
fi

# Read Caddyfile template
CADDYFILE_TEMPLATE=$(cat azure-configs/Caddyfile.template)
echo -e "${GREEN}✅ Template loaded${NC}"

echo ""
echo -e "${YELLOW}[2/5] Extracting Terraform variables...${NC}"

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}❌ Error: terraform/terraform.tfvars not found${NC}"
    exit 1
fi

# Extract variables
DOMAIN_NAME=$(grep "^domain_name" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_CLIENT_IP=$(grep "^wireguard_client_ip" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
ADMIN_USER=$(grep "^admin_username" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

echo -e "${GREEN}✅ Variables extracted${NC}"
echo "   Domain: $DOMAIN_NAME"
echo "   WireGuard Client IP: $WIREGUARD_CLIENT_IP"

echo ""
echo -e "${YELLOW}[3/5] Processing template...${NC}"

# Replace template variables
CADDYFILE_CONTENT=$(echo "$CADDYFILE_TEMPLATE" | \
    sed "s|{{DOMAIN_NAME}}|$DOMAIN_NAME|g" | \
    sed "s|{{WIREGUARD_CLIENT_IP}}|$WIREGUARD_CLIENT_IP|g")

echo -e "${GREEN}✅ Template processed${NC}"

echo ""
echo -e "${YELLOW}[4/5] Connecting to Azure VM...${NC}"

# Get Azure VM IP
if [ ! -f "terraform.tfstate" ]; then
    echo -e "${RED}❌ Error: Terraform state not found. Deploy infrastructure first.${NC}"
    exit 1
fi

VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null)

if [ -z "$VM_IP" ]; then
    echo -e "${RED}❌ Error: Could not get VM IP from Terraform${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Connected to: $VM_IP${NC}"

echo ""
echo -e "${YELLOW}[5/5] Updating Caddy configuration...${NC}"

# Create temporary file
TEMP_FILE=$(mktemp)
echo "$CADDYFILE_CONTENT" > "$TEMP_FILE"

# Upload new Caddyfile
if ! scp -o StrictHostKeyChecking=no "$TEMP_FILE" $ADMIN_USER@$VM_IP:/tmp/Caddyfile.new 2>/dev/null; then
    echo -e "${RED}❌ Error: Failed to upload config${NC}"
    echo "   Check SSH access: ssh $ADMIN_USER@$VM_IP"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Install and reload Caddy
ssh -o StrictHostKeyChecking=no $ADMIN_USER@$VM_IP << 'ENDSSH'
# Backup current config
sudo cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup

# Install new config
sudo mv /tmp/Caddyfile.new /etc/caddy/Caddyfile
sudo chown caddy:caddy /etc/caddy/Caddyfile
sudo chmod 644 /etc/caddy/Caddyfile

# Test config
if sudo caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
    echo "✅ Config validation passed"
    # Reload Caddy
    if sudo systemctl reload caddy; then
        echo "✅ Caddy reloaded successfully"
        exit 0
    else
        echo "❌ Failed to reload Caddy"
        sudo cp /etc/caddy/Caddyfile.backup /etc/caddy/Caddyfile
        exit 1
    fi
else
    echo "❌ Config validation failed"
    sudo cp /etc/caddy/Caddyfile.backup /etc/caddy/Caddyfile
    exit 1
fi
ENDSSH

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      ✅ Caddy Configuration Updated!                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✨ Update completed in seconds (vs ~10 minutes for full redeployment)${NC}"
    echo ""
    echo -e "${BLUE}💡 Tip: View Caddy logs to verify:${NC}"
    echo -e "   ${GREEN}ssh $ADMIN_USER@$VM_IP 'sudo journalctl -u caddy -f'${NC}"
else
    echo ""
    echo -e "${RED}❌ Update failed - config reverted to backup${NC}"
    exit 1
fi

# Cleanup
rm -f "$TEMP_FILE"
cd ..
