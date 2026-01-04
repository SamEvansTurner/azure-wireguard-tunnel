#!/bin/bash
# =============================================================================
# Azure WireGuard Tunnel - Unified Deployment Script
# =============================================================================
#
# This script orchestrates the complete deployment:
# 1. Validates config.yml
# 2. Converts config to Terraform tfvars
# 3. Runs Terraform to provision Azure infrastructure
# 4. Generates Ansible inventory from Terraform outputs
# 5. Runs Ansible to configure the VM
#
# Usage:
#   ./scripts/deploy.sh              # Full deployment
#   ./scripts/deploy.sh --plan       # Plan only (no changes)
#   ./scripts/deploy.sh --ansible    # Skip Terraform, run Ansible only
#   ./scripts/deploy.sh --destroy    # Destroy infrastructure
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
CONFIG_FILE="${PROJECT_ROOT}/config.yml"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
# Use a native Linux filesystem path for venv to avoid WSL/Windows filesystem performance issues
VENV_DIR="${HOME}/.cache/azure-wireguard-tunnel/.venv"

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

setup_ssh_agent() {
    # Setup ssh-agent and add the SSH key to avoid multiple passphrase prompts
    local ssh_key=$(get_yaml_value "ssh.private_key_path")
    ssh_key="${ssh_key/#\~/$HOME}"
    
    if [[ ! -f "$ssh_key" ]]; then
        log_warning "SSH key not found: $ssh_key"
        return 0
    fi
    
    # Check if key is already loaded in agent
    if ssh-add -l 2>/dev/null | grep -q "$(ssh-keygen -lf "$ssh_key" 2>/dev/null | awk '{print $2}')"; then
        log_info "SSH key already loaded in agent"
        return 0
    fi
    
    # Start ssh-agent if not running
    if [[ -z "${SSH_AUTH_SOCK:-}" ]]; then
        log_info "Starting ssh-agent..."
        eval "$(ssh-agent -s)" > /dev/null
    fi
    
    # Add the key (will prompt for passphrase if needed)
    log_info "Adding SSH key to agent (you may be prompted for your passphrase)..."
    ssh-add "$ssh_key"
    log_success "SSH key added to agent"
}

check_dependencies() {
    local missing=()
    
    if ! command -v terraform &> /dev/null; then
        missing+=("terraform")
    fi
    
    if ! command -v ansible-playbook &> /dev/null; then
        missing+=("ansible")
    fi
    
    if ! command -v python3 &> /dev/null; then
        missing+=("python3")
    fi
    
    if ! command -v yq &> /dev/null; then
        log_warning "yq not found - will use Python for YAML parsing"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Please install the missing tools and try again."
        exit 1
    fi
}

setup_python_venv() {
    # Create virtual environment if it doesn't exist
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Creating Python virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi
    
    # Activate virtual environment
    # shellcheck disable=SC1091
    source "${VENV_DIR}/bin/activate"
    
    # Install/upgrade requirements
    if [[ -f "${SCRIPT_DIR}/requirements.txt" ]]; then
        pip install -q --upgrade pip
        pip install -q -r "${SCRIPT_DIR}/requirements.txt"
    fi
    
    log_success "Python environment ready"
}

check_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Config file not found: $CONFIG_FILE"
        echo ""
        echo "To get started:"
        echo "  1. cp config.yml.example config.yml"
        echo "  2. Edit config.yml with your settings"
        echo "  3. Run this script again"
        exit 1
    fi
    
    log_info "Validating config.yml..."
    if ! python3 "${SCRIPT_DIR}/yaml-to-tfvars.py" "$CONFIG_FILE" --validate; then
        log_error "Configuration validation failed"
        exit 1
    fi
    log_success "Configuration is valid"
}

get_yaml_value() {
    # Extract a value from YAML using Python (cross-platform)
    local key="$1"
    python3 -c "
import yaml
with open('$CONFIG_FILE', 'r') as f:
    config = yaml.safe_load(f)
keys = '$key'.split('.')
value = config
for k in keys:
    if value is None:
        value = ''
        break
    value = value.get(k, '')
print(value if value else '')
"
}

generate_tfvars() {
    log_info "Generating Terraform variables from config.yml..."
    python3 "${SCRIPT_DIR}/yaml-to-tfvars.py" "$CONFIG_FILE" -o "${TERRAFORM_DIR}/terraform.tfvars"
    log_success "Generated: terraform/terraform.tfvars"
}

run_terraform() {
    local action="${1:-apply}"
    
    cd "$TERRAFORM_DIR"
    
    if [[ ! -f ".terraform/terraform.tfstate" ]] && [[ ! -d ".terraform" ]]; then
        log_info "Initializing Terraform..."
        terraform init
    fi
    
    case "$action" in
        plan)
            log_info "Running Terraform plan..."
            terraform plan
            ;;
        apply)
            log_info "Running Terraform apply..."
            # First apply: target just the VM to ensure managed identity is created
            # This is needed because role assignments reference the identity's principal_id
            # which doesn't exist until the identity is actually provisioned
            terraform apply -auto-approve -target=azurerm_linux_virtual_machine.main
            
            # Second apply: create all remaining resources (including role assignments)
            log_info "Running Terraform apply to finalize role assignments..."
            terraform apply -auto-approve
            ;;
        destroy)
            log_warning "This will destroy all Azure resources!"
            read -p "Are you sure? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                terraform destroy -auto-approve
                log_success "Infrastructure destroyed"
            else
                log_info "Destroy cancelled"
            fi
            exit 0
            ;;
    esac
    
    cd "$PROJECT_ROOT"
}

get_terraform_outputs() {
    cd "$TERRAFORM_DIR"
    VM_IP=$(terraform output -raw vm_public_ip 2>/dev/null || echo "")
    SUBSCRIPTION_ID=$(terraform output -raw subscription_id 2>/dev/null || echo "")
    cd "$PROJECT_ROOT"
    
    if [[ -z "$VM_IP" ]]; then
        log_error "Could not get VM IP from Terraform outputs"
        log_info "Make sure Terraform has been applied successfully"
        exit 1
    fi
    
    log_success "VM Public IP: $VM_IP"
    if [[ -n "$SUBSCRIPTION_ID" ]]; then
        log_success "Subscription ID: $SUBSCRIPTION_ID (auto-detected)"
    fi
}

generate_ansible_inventory() {
    log_info "Generating Ansible inventory..."
    
    local admin_user=$(get_yaml_value "ssh.admin_username")
    local ssh_key=$(get_yaml_value "ssh.private_key_path")
    
    # Expand ~ in path
    ssh_key="${ssh_key/#\~/$HOME}"
    
    mkdir -p "${ANSIBLE_DIR}/inventory"
    
    cat > "${ANSIBLE_DIR}/inventory/azure.yml" <<EOF
---
# Auto-generated from deploy.sh
# VM IP: ${VM_IP}
all:
  hosts:
    azure_vm:
      ansible_host: "${VM_IP}"
      ansible_user: "${admin_user}"
      ansible_ssh_private_key_file: "${ssh_key}"
      ansible_python_interpreter: /usr/bin/python3
  vars:
    ansible_connection: ssh
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
    # Azure subscription ID - auto-detected from Terraform
    azure_subscription_id: "${SUBSCRIPTION_ID}"
EOF
    
    log_success "Generated: ansible/inventory/azure.yml"
}

wait_for_ssh() {
    log_info "Waiting for VM to be ready (SSH)..."
    
    local admin_user=$(get_yaml_value "ssh.admin_username")
    local ssh_key=$(get_yaml_value "ssh.private_key_path")
    ssh_key="${ssh_key/#\~/$HOME}"
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -i "$ssh_key" "${admin_user}@${VM_IP}" 'echo ready' 2>/dev/null; then
            log_success "VM is ready"
            return 0
        fi
        echo -n "."
        sleep 10
        ((attempt++))
    done
    
    echo ""
    log_error "Timeout waiting for VM to be ready"
    exit 1
}

run_ansible() {
    log_info "Running Ansible playbook..."
    
    cd "$ANSIBLE_DIR"
    
    # Set ANSIBLE_CONFIG explicitly to avoid world-writable directory issues on WSL
    # Use ansible-playbook from venv to ensure correct version (supports Python 3.12 on remote)
    ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" "${VENV_DIR}/bin/ansible-playbook" \
        -i inventory/azure.yml \
        playbooks/setup.yml \
        -e "@${CONFIG_FILE}"
    
    cd "$PROJECT_ROOT"
    log_success "Ansible configuration complete"
}

show_completion_info() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}Deployment Complete!${NC}"
    echo "=============================================="
    echo ""
    echo "VM Public IP: ${VM_IP}"
    echo ""
    echo "Next steps:"
    echo "  1. Configure WireGuard on your home network"
    echo "  2. Update wireguard.client_public_key in config.yml"
    echo "  3. Re-run: ./scripts/deploy.sh --ansible"
    echo ""
    echo "Useful commands:"
    echo "  SSH to VM:       ssh $(get_yaml_value 'ssh.admin_username')@${VM_IP}"
    echo "  Check WireGuard: sudo wg show"
    echo "  Check services:  sudo systemctl status caddy wireguard-wg0"
    echo ""
    
    if [[ "$(get_yaml_value 'bandwidth_monitor.enabled')" == "True" ]] || \
       [[ "$(get_yaml_value 'bandwidth_monitor.enabled')" == "true" ]]; then
        echo "Bandwidth Monitor:"
        echo "  Check status:    sudo /opt/bandwidth-monitor/monitor-costs.py status"
        echo "  View logs:       sudo tail -f /var/log/bandwidth-monitor.log"
        echo ""
    fi
    
    echo "=============================================="
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    local action="full"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --plan)
                action="plan"
                shift
                ;;
            --ansible|--ansible-only)
                action="ansible"
                shift
                ;;
            --destroy)
                action="destroy"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --plan      Plan Terraform changes only"
                echo "  --ansible   Skip Terraform, run Ansible only"
                echo "  --destroy   Destroy all infrastructure"
                echo "  --help      Show this help"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "=============================================="
    echo "Azure WireGuard Tunnel Deployment"
    echo "=============================================="
    echo ""
    
    # Check dependencies
    check_dependencies
    
    # Setup Python virtual environment
    setup_python_venv
    
    # Check config exists and is valid
    check_config
    
    case "$action" in
        plan)
            generate_tfvars
            run_terraform plan
            ;;
        ansible)
            setup_ssh_agent
            get_terraform_outputs
            generate_ansible_inventory
            run_ansible
            show_completion_info
            ;;
        destroy)
            generate_tfvars
            run_terraform destroy
            ;;
        full)
            generate_tfvars
            run_terraform apply
            get_terraform_outputs
            generate_ansible_inventory
            setup_ssh_agent
            wait_for_ssh
            run_ansible
            show_completion_info
            ;;
    esac
}

main "$@"
