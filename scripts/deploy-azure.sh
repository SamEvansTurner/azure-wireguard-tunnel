#!/bin/bash
# Azure WireGuard Secure Tunnel - Deployment Script
# Deploys the complete Azure infrastructure using Terraform with config templates

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Azure WireGuard Secure Tunnel - Deployment      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running from project root
if [ ! -d "terraform" ]; then
    echo -e "${RED}❌ Error: Must run from project root directory${NC}"
    echo "   Current directory: $(pwd)"
    exit 1
fi

echo -e "${YELLOW}[1/7] Checking configuration templates...${NC}"

# Check if azure-configs/ exists
if [ ! -d "azure-configs" ]; then
    echo -e "${YELLOW}⚠️  First run - copying example configs...${NC}"
    cp -r azure-configs.example azure-configs
    echo -e "${GREEN}✅ Created azure-configs/ directory${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: Configure templates before deploying:${NC}"
    echo ""
    echo "1. Edit WireGuard template with your home public key:"
    echo -e "   ${GREEN}nano azure-configs/wg0-server.conf.template${NC}"
    echo "   Replace PLACEHOLDER_HOME_PUBLIC_KEY with your home's key"
    echo "   Get it from home server: docker-compose exec wireguard cat /config/publickey"
    echo ""
    echo "2. Customize Caddyfile for your services:"
    echo -e "   ${GREEN}nano azure-configs/Caddyfile.template${NC}"
    echo ""
    echo "Then run this script again to deploy."
    exit 0
fi

# Check if templates have placeholders
if grep -q "PLACEHOLDER_HOME_PUBLIC_KEY" azure-configs/wg0-server.conf.template; then
    echo -e "${RED}❌ Error: WireGuard template still has PLACEHOLDER_HOME_PUBLIC_KEY${NC}"
    echo ""
    echo "Please edit azure-configs/wg0-server.conf.template and add your home's"
    echo "WireGuard public key (get from: docker-compose exec wireguard cat /config/publickey)"
    exit 1
fi

echo -e "${GREEN}✅ Configuration templates found${NC}"

cd terraform

echo -e "${YELLOW}[2/7] Checking prerequisites...${NC}"

# Check Terraform
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}❌ Terraform not found. Please install: https://www.terraform.io/downloads${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Terraform found: $(terraform version -json | jq -r '.terraform_version')${NC}"

# Check Azure CLI
if ! command -v az &> /dev/null; then
    echo -e "${RED}❌ Azure CLI not found. Please install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Azure CLI found${NC}"

# Check Azure login
if ! az account show &> /dev/null; then
    echo -e "${RED}❌ Not logged into Azure. Run: az login${NC}"
    exit 1
fi
AZURE_ACCOUNT=$(az account show --query name -o tsv)
echo -e "${GREEN}✅ Logged into Azure: $AZURE_ACCOUNT${NC}"

echo ""
echo -e "${YELLOW}[3/7] Validating configuration...${NC}"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}❌ terraform.tfvars not found${NC}"
    echo ""
    echo "Please create terraform.tfvars from the example:"
    echo "  cp terraform.tfvars.example terraform.tfvars"
    echo "  nano terraform.tfvars"
    echo ""
    exit 1
fi

# Check for CHANGEME placeholders
if grep -q "CHANGEME" terraform.tfvars; then
    echo -e "${RED}❌ Found CHANGEME placeholder in terraform.tfvars${NC}"
    echo "Please configure all required values in terraform.tfvars"
    exit 1
fi

# Extract variables from terraform.tfvars
DOMAIN_NAME=$(grep "^domain_name" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_SERVER_IP=$(grep "^wireguard_server_ip" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_CLIENT_IP=$(grep "^wireguard_client_ip" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
WIREGUARD_PORT=$(grep "^wireguard_port" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')

# Extract and validate SSH key path
SSH_KEY_PATH=$(grep ssh_public_key_path terraform.tfvars | cut -d'=' -f2 | tr -d ' "' | sed 's/~/$HOME/g')
SSH_KEY_PATH=$(eval echo $SSH_KEY_PATH)
if [ ! -f "$SSH_KEY_PATH" ]; then
    echo -e "${RED}❌ SSH public key not found: $SSH_KEY_PATH${NC}"
    echo ""
    echo "Generate an SSH key with:"
    echo "  ssh-keygen -t ed25519 -C \"your@email.com\""
    echo ""
    exit 1
fi
echo -e "${GREEN}✅ SSH public key found: $SSH_KEY_PATH${NC}"

# Validate admin username
ADMIN_USER=$(grep "^admin_username" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [[ "$ADMIN_USER" =~ ^(admin|root|azureuser|ubuntu|administrator)$ ]]; then
    echo -e "${YELLOW}⚠️  Warning: Using common username '$ADMIN_USER'${NC}"
    echo "   Consider using a unique username for better security"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check for IPv4 address
IPV4_ADDR=$(grep "^allowed_ssh_ipv4" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ -n "$IPV4_ADDR" ]; then
    echo -e "${GREEN}✅ IPv4 SSH whitelist: $IPV4_ADDR${NC}"
fi

# Check for optional IPv6 address
IPV6_ADDR=$(grep "^allowed_ssh_ipv6" terraform.tfvars | cut -d'=' -f2 | tr -d ' "')
if [ -n "$IPV6_ADDR" ] && [ "$IPV6_ADDR" != '""' ] && [ "$IPV6_ADDR" != "''" ]; then
    echo -e "${GREEN}✅ IPv6 SSH whitelist: $IPV6_ADDR${NC}"
else
    echo -e "${BLUE}ℹ️  IPv6 not configured (optional)${NC}"
fi

echo -e "${GREEN}✅ Configuration validated${NC}"

echo ""
echo -e "${YELLOW}[4/7] Processing configuration templates...${NC}"

# Read templates
CADDYFILE_TEMPLATE=$(cat ../azure-configs/Caddyfile.template)
WG_TEMPLATE=$(cat ../azure-configs/wg0-server.conf.template)

# Replace template variables
# Note: {{WIREGUARD_SERVER_PRIVATE_KEY}} is replaced by cloud-init during deployment
CADDYFILE_CONTENT=$(echo "$CADDYFILE_TEMPLATE" | \
    sed "s|{{DOMAIN_NAME}}|$DOMAIN_NAME|g" | \
    sed "s|{{WIREGUARD_CLIENT_IP}}|$WIREGUARD_CLIENT_IP|g")

WG_CONTENT=$(echo "$WG_TEMPLATE" | \
    sed "s|{{WIREGUARD_SERVER_IP}}|$WIREGUARD_SERVER_IP|g" | \
    sed "s|{{WIREGUARD_CLIENT_IP}}|$WIREGUARD_CLIENT_IP|g" | \
    sed "s|{{WIREGUARD_PORT}}|$WIREGUARD_PORT|g")

# Export as environment variables for Terraform
export TF_VAR_azure_caddyfile_content="$CADDYFILE_CONTENT"
export TF_VAR_azure_wireguard_config="$WG_CONTENT"

echo -e "${GREEN}✅ Templates processed and ready for deployment${NC}"

echo ""
echo -e "${YELLOW}[5/7] Initializing Terraform...${NC}"
terraform init

echo ""
echo -e "${YELLOW}[6/7] Planning deployment...${NC}"
echo ""
terraform plan -out=tfplan

echo ""
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Review the plan above carefully!${NC}"
echo -e "${BLUE}════════════════════════════════════════════════${NC}"
echo ""
read -p "Deploy this infrastructure? (yes/no) " -r
echo
if [[ ! $REPLY == "yes" ]]; then
    echo "Deployment cancelled"
    rm -f tfplan
    exit 0
fi

echo ""
echo -e "${YELLOW}[7/7] Deploying infrastructure...${NC}"
echo -e "${BLUE}This will take approximately 5-10 minutes${NC}"
echo ""

terraform apply tfplan
rm -f tfplan

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║          ✅ Deployment Successful!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
echo ""

# Display outputs
terraform output -json > /tmp/tf-outputs.json

VM_IP=$(jq -r '.vm_public_ip.value' /tmp/tf-outputs.json)
SSH_CMD=$(jq -r '.ssh_connection.value' /tmp/tf-outputs.json)
COST=$(jq -r '.estimated_monthly_cost.value' /tmp/tf-outputs.json)

echo -e "${BLUE}📊 Deployment Information:${NC}"
echo ""
echo -e "  Public IP:     ${GREEN}$VM_IP${NC}"
echo -e "  SSH:           ${GREEN}$SSH_CMD${NC}"
echo -e "  Monthly Cost:  ${GREEN}$COST${NC}"
echo ""

echo -e "${YELLOW}⏳ Waiting for cloud-init to complete (~5 minutes)...${NC}"
echo "   This configures WireGuard, Caddy, security, etc."
echo ""

# Wait for cloud-init using a single SSH connection
sleep 10
echo "Connecting to VM to monitor cloud-init progress..."
if ssh -o StrictHostKeyChecking=no -t $ADMIN_USER@$VM_IP 'bash -s' << 'ENDSSH'
    echo "Checking cloud-init status..."
    for i in {1..60}; do
        if [ -f /var/lib/cloud/instance/boot-finished ]; then
            echo "✅ Cloud-init completed!"
            exit 0
        fi
        if [ $i -eq 60 ]; then
            echo "⚠️  Cloud-init still running after 5 minutes"
            exit 1
        fi
        echo -n "."
        sleep 5
    done
ENDSSH
then
    echo ""
    echo -e "${GREEN}✅ Cloud-init completed successfully!${NC}"
else
    echo ""
    echo -e "${YELLOW}⚠️  Cloud-init still running. You can check manually with:${NC}"
    echo "   $SSH_CMD 'tail -f /var/log/cloud-init-output.log'"
fi

echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo ""
echo "1. Get Azure WireGuard public key:"
echo -e "   ${GREEN}$SSH_CMD 'sudo cat /etc/wireguard/publickey'${NC}"
echo ""
echo "2. On your home server, update home-configs/wireguard/wg0.conf:"
echo "   - PublicKey = <Azure public key from step 1>"
echo "   - Endpoint = $VM_IP:51820"
echo ""
echo "3. Restart home WireGuard:"
echo -e "   ${GREEN}docker-compose restart wireguard${NC}"
echo ""
echo "4. Test tunnel connectivity:"
echo -e "   ${GREEN}ping 10.0.0.1${NC}"
echo ""
echo "5. Sync SSL certificates:"
echo -e "   ${GREEN}./scripts/sync-certs.sh${NC}"
echo ""
echo "6. Validate deployment:"
echo -e "   ${GREEN}./scripts/validate.sh${NC}"
echo ""
echo -e "${BLUE}💡 Tip: To update Caddy config without redeploying:${NC}"
echo -e "   ${GREEN}./scripts/update-caddy-config.sh${NC}"
echo ""

rm -f /tmp/tf-outputs.json

cd ..
