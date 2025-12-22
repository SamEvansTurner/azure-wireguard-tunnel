#!/bin/bash
# Azure WireGuard Secure Tunnel - Fast WireGuard Peer Update
# Updates WireGuard peer configuration on Azure VM without recreating infrastructure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Fast WireGuard Peer Configuration Update        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running from project root
if [ ! -d "terraform" ] || [ ! -d "azure-configs" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo -e "${YELLOW}[1/5] Reading configuration template...${NC}"

if [ ! -f "azure-configs/wg0-server.conf.template" ]; then
    echo -e "${RED}❌ Error: azure-configs/wg0-server.conf.template not found${NC}"
    echo "Run ./scripts/deploy-azure.sh first to set up configs"
    exit 1
fi

# Read WireGuard template
WG_TEMPLATE=$(cat azure-configs/wg0-server.conf.template)

# Check if template has placeholder
if echo "$WG_TEMPLATE" | grep -q "PLACEHOLDER_HOME_PUBLIC_KEY"; then
    echo -e "${RED}❌ Error: Template still has PLACEHOLDER_HOME_PUBLIC_KEY${NC}"
    echo "Please edit azure-configs/wg0-server.conf.template with your home's public key"
    exit 1
fi

echo -e "${GREEN}✅ Template loaded${NC}"

echo ""
echo -e "${YELLOW}[2/5] Extracting Terraform variables...${NC}"

cd terraform

if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}❌ Error: terraform/terraform.tfvars not found${NC}"
    exit 1
fi

# Extract variables
WIREGUARD_SERVER_IP=$(grep "^wireguard_server_ip" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_CLIENT_IP=$(grep "^wireguard_client_ip" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_PORT=$(grep "^wireguard_port" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
ADMIN_USER=$(grep "^admin_username" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

echo -e "${GREEN}✅ Variables extracted${NC}"
echo "   Server IP: $WIREGUARD_SERVER_IP"
echo "   Client IP: $WIREGUARD_CLIENT_IP"
echo "   Port: $WIREGUARD_PORT"

echo ""
echo -e "${YELLOW}[3/5] Processing template...${NC}"

# Replace template variables (except private key which stays as placeholder)
WG_CONTENT=$(echo "$WG_TEMPLATE" | \
    sed "s|{{WIREGUARD_SERVER_IP}}|$WIREGUARD_SERVER_IP|g" | \
    sed "s|{{WIREGUARD_CLIENT_IP}}|$WIREGUARD_CLIENT_IP|g" | \
    sed "s|{{WIREGUARD_PORT}}|$WIREGUARD_PORT|g")

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
echo -e "${YELLOW}[5/5] Updating WireGuard configuration...${NC}"

# Create temporary file
TEMP_FILE=$(mktemp)
echo "$WG_CONTENT" > "$TEMP_FILE"

# Upload new config
if ! scp -o StrictHostKeyChecking=no "$TEMP_FILE" $ADMIN_USER@$VM_IP:/tmp/wg0.conf.new 2>/dev/null; then
    echo -e "${RED}❌ Error: Failed to upload config${NC}"
    echo "   Check SSH access: ssh $ADMIN_USER@$VM_IP"
    rm -f "$TEMP_FILE"
    exit 1
fi

# Install and reload WireGuard
ssh -o StrictHostKeyChecking=no $ADMIN_USER@$VM_IP << 'ENDSSH'
# Get current private key from running config
CURRENT_PRIVATE_KEY=$(sudo wg show wg0 private-key 2>/dev/null || sudo cat /etc/wireguard/privatekey 2>/dev/null)

if [ -z "$CURRENT_PRIVATE_KEY" ]; then
    echo "❌ Could not get current WireGuard private key"
    exit 1
fi

# Backup current config
sudo cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.backup

# Install new config and replace private key placeholder
sudo mv /tmp/wg0.conf.new /etc/wireguard/wg0.conf
sudo sed -i "s|{{WIREGUARD_SERVER_PRIVATE_KEY}}|$CURRENT_PRIVATE_KEY|" /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# Restart WireGuard
if sudo systemctl restart wg-quick@wg0; then
    echo "✅ WireGuard restarted successfully"
    
    # Give it a moment to start
    sleep 2
    
    # Verify it's running
    if sudo wg show wg0 > /dev/null 2>&1; then
        echo "✅ WireGuard is running"
        exit 0
    else
        echo "❌ WireGuard failed to start"
        sudo cp /etc/wireguard/wg0.conf.backup /etc/wireguard/wg0.conf
        sudo systemctl restart wg-quick@wg0
        exit 1
    fi
else
    echo "❌ Failed to restart WireGuard"
    sudo cp /etc/wireguard/wg0.conf.backup /etc/wireguard/wg0.conf
    exit 1
fi
ENDSSH

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║    ✅ WireGuard Configuration Updated!              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${GREEN}✨ Update completed in seconds (vs ~10 minutes for full redeployment)${NC}"
    echo ""
    echo -e "${BLUE}💡 Tip: Check WireGuard status:${NC}"
    echo -e "   ${GREEN}ssh $ADMIN_USER@$VM_IP 'sudo wg show'${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Note: You may need to restart home WireGuard if peer settings changed${NC}"
else
    echo ""
    echo -e "${RED}❌ Update failed - config reverted to backup${NC}"
    exit 1
fi

# Cleanup
rm -f "$TEMP_FILE"
cd ..
