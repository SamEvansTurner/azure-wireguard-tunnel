# Terraform Configuration Guide

This directory contains the Terraform Infrastructure as Code (IaC) for deploying the Azure WireGuard Secure Tunnel.

## Quick Start

```bash
# 1. Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# 2. Edit with your details
nano terraform.tfvars

# 3. Deploy (or use deploy-azure.sh from project root)
terraform init
terraform plan
terraform apply
```

## Configuration Variables Reference

### Azure Configuration

#### `location` (required)
**Type:** `string`  
**Description:** Azure region where resources will be deployed  
**Example:** `"australiaeast"`

**Common regions:**
- `australiaeast` - Sydney, Australia
- `eastus` - Virginia, USA
- `westeurope` - Netherlands, Europe
- `southeastasia` - Singapore, Asia
- `uksouth` - London, UK

**💡 Tip:** Choose a region close to you for lower latency and potentially lower costs.

#### `resource_group_name` (required)
**Type:** `string`  
**Description:** Name for the Azure resource group (container for all resources)  
**Example:** `"rg-secure-tunnel"`

**Best practices:**
- Use descriptive names with prefixes (e.g., `rg-`, `prod-`, `dev-`)
- Keep it short and readable
- Avoid special characters except hyphens

---

### VM Configuration

#### `admin_username` (required)
**Type:** `string`  
**Description:** Administrator username for SSH access to the Azure VM  
**Example:** `"yourusername"`

**⚠️ Important restrictions:**
- Cannot be: `admin`, `administrator`, `root`, `azureuser`, `user`
- Must be lowercase alphanumeric (no special characters)
- Must start with a letter
- Maximum 64 characters

**💡 Tip:** Use your personal username or something unique to you.

#### `ssh_public_key_path` (required)
**Type:** `string`  
**Description:** Path to your SSH public key file for VM access  
**Example:** `"~/.ssh/id_rsa.pub"`

**⚠️ Important restrictions:**
- Must be RSA key (Azure restriction)

**Common locations:**
- `~/.ssh/id_rsa.pub` - RSA key

**Generate if needed:**
```bash
ssh-keygen -t rsa -b 4096 -C "azure-vm-admin"
```

#### `allowed_ssh_ipv4` (required)
**Type:** `string` (CIDR notation)  
**Description:** Your home public IPv4 address for SSH access restriction  
**Example:** `"1.2.3.4/32"`

**Format:** `IP_ADDRESS/32` (the `/32` means exactly one IP)

**Find your IP:**
```bash
curl -4 ifconfig.me
```

**💡 Tip:** Add `/32` to your IP address for maximum security (only your IP can SSH)

#### `allowed_ssh_ipv6` (optional)
**Type:** `string` (CIDR notation)  
**Description:** Your home public IPv6 address for SSH access restriction  
**Example:** `"2001:db8::1/128"`
**Default:** `null` (IPv6 SSH access disabled)

**Find your IPv6:**
```bash
curl -6 ifconfig.me
```

**💡 Tip:** Only set this if you have a stable IPv6 address

---

### Domain Configuration

#### `domain_name` (required)
**Type:** `string`  
**Description:** Your service subdomain (where services will be accessed)  
**Example:** `"svc.example.com"`

**Pattern:** `svc.yourdomain.com` or any subdomain you prefer

**Requirements:**
- Must be managed by deSEC.io
- Must have a wildcard certificate for `*.svc.example.com`
- DNS will be automatically updated on VM boot

#### `subdomain` (required)
**Type:** `string`  
**Description:** Subdomain pattern for DNS records  
**Example:** `"*"`
**Default:** `"*"` (wildcard)

**Common values:**
- `"*"` - Wildcard (*.svc.example.com)
- Specific subdomain if needed

**💡 Tip:** Keep as `"*"` for wildcard SSL certificate compatibility

#### `desec_token` (required)
**Type:** `string` (sensitive)  
**Description:** deSEC.io API token for automatic DNS updates  
**Example:** `"your_desec_api_token_here"`

**How to get:**
1. Log in to [deSEC.io](https://desec.io)
2. Navigate to **Token Management**
3. Create a new token with **read/write** permissions
4. Copy and save securely

**⚠️ Security:** This token is sensitive! Don't commit it to Git.

---

### WireGuard Configuration

#### `wireguard_server_ip` (required)
**Type:** `string`  
**Description:** WireGuard server (Azure VM) IP address in tunnel network  
**Example:** `"10.0.0.1"`
**Default:** `"10.0.0.1"`

**💡 Tip:** Keep default unless you have IP conflicts

#### `wireguard_client_ip` (required)
**Type:** `string`  
**Description:** WireGuard client (home server) IP address in tunnel network  
**Example:** `"10.0.0.2"`
**Default:** `"10.0.0.2"`

**💡 Tip:** Keep default unless you have IP conflicts

#### `wireguard_port` (required)
**Type:** `number`  
**Description:** UDP port for WireGuard tunnel  
**Example:** `51820`
**Default:** `51820`

**Common ports:**
- `51820` - Standard WireGuard port (recommended)
- `443` - Masquerade as HTTPS (for restrictive networks)
- Any high port (1024-65535)

**💡 Tip:** Use default unless you have firewall restrictions

---

## Example Configuration

### Minimal Configuration

```hcl
# terraform.tfvars - Minimal required configuration

# Azure
location            = "australiaeast"
resource_group_name = "rg-secure-tunnel"

# VM Access
admin_username      = "myusername"
ssh_public_key_path = "~/.ssh/id_ed25519.pub"
allowed_ssh_ipv4    = "1.2.3.4/32"

# Domain
domain_name = "svc.example.com"
subdomain   = "*"
desec_token = "your_desec_token_here"

# WireGuard (defaults work fine)
wireguard_server_ip = "10.0.0.1"
wireguard_client_ip = "10.0.0.2"
wireguard_port      = 51820
```

---

## Deployment Commands

### Using Deploy Script (Recommended)

```bash
# From project root - handles validation and template processing
./scripts/deploy-azure.sh
```

### Destroy Resources

```bash
terraform destroy
```

**⚠️ Warning:** This will delete all Azure resources. Ensure you have backups!

---

## Variable Validation

Terraform will validate your configuration before deployment:

✅ **Checked automatically:**
- `admin_username` not in restricted list
- `allowed_ssh_ipv4` is valid CIDR format
- `allowed_ssh_ipv6` is valid CIDR format (if provided)
- `domain_name` is a valid domain
- `wireguard_port` is in valid range (1-65535)

---

## Troubleshooting

### "Invalid CIDR notation"

**Problem:** `allowed_ssh_ipv4` or `allowed_ssh_ipv6` format incorrect

**Solution:**
```bash
# IPv4 - Add /32 for single IP
allowed_ssh_ipv4 = "1.2.3.4/32"

# IPv6 - Add /128 for single IP
allowed_ssh_ipv6 = "2001:db8::1/128"
```

### "Admin username is restricted"

**Problem:** Using `admin`, `administrator`, `root`, etc.

**Solution:** Choose a different username:
```hcl
admin_username = "myname"  # ✅ Valid
admin_username = "admin"   # ❌ Invalid
```

### "SSH key not found"

**Problem:** Path to SSH public key is incorrect

**Solution:**
```bash
# Check if key exists
ls ~/.ssh/id_rsa.pub

# Generate if missing
ssh-keygen -t rsa -b 4096 -C "azure-vm-admin"

# Use full path if needed
ssh_public_key_path = "/home/username/.ssh/id_rsa.pub"
```

### "deSEC token invalid"

**Problem:** Token not working for DNS updates

**Solution:**
1. Verify token has **read/write** permissions
2. Check token hasn't expired
3. Ensure domain is correctly managed by deSEC
4. Test token manually:
```bash
curl -X GET -H "Authorization: Token your_token" \
  "https://desec.io/api/v1/domains/"
```

---

## Security Best Practices

### Secrets Management
- ✅ Keep `terraform.tfvars` out of version control (already in .gitignore)
- ✅ Use environment variables for sensitive data if preferred:
  ```bash
  export TF_VAR_desec_token="your_token"
  terraform apply
  ```
- ✅ Rotate deSEC tokens periodically
- ✅ Use different tokens for different environments

### Network Security
- ✅ Keep allowed IPs as restrictive as possible
- ✅ Update `allowed_ssh_ipv4` if your home IP changes
- ✅ Use non-standard WireGuard port if concerned about scanning

---

## Related Documentation

- [Main README](../README.md) - Project overview and setup
- [Template System](../docs/TEMPLATE-SYSTEM.md) - Configuration management
- [Deploy Script](../scripts/deploy-azure.sh) - Automated deployment

---

## Outputs

After successful deployment, Terraform will output:

- `vm_public_ip` - Azure VM public IP address
- `vm_fqdn` - Fully qualified domain name
- `wireguard_server_public_key` - WireGuard public key for home configuration
- `ssh_connection_command` - Ready-to-use SSH command

Save these outputs! You'll need them for connecting your home server.
