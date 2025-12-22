# Azure Configuration Template System

This guide explains how to use the template-based configuration system for fast, iterative deployment updates.

## Overview

The template system separates your service configurations from the infrastructure deployment, allowing you to:

- **Edit services in seconds** instead of waiting 10 minutes for VM recreation
- **Version control your configs** separately from infrastructure
- **Test changes quickly** without full redeployment
- **Keep configs DRY** (Don't Repeat Yourself)

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Local Configuration Templates                          │
│  (azure-configs/)                                       │
│                                                         │
│  ┌──────────────────────┐  ┌─────────────────────────┐│
│  │ Caddyfile.template   │  │ wg0-server.conf.template││
│  │                      │  │                          ││
│  │ Service whitelist    │  │ Home WG public key      ││
│  │ {{DOMAIN_NAME}}      │  │ {{WIREGUARD_SERVER_IP}} ││
│  └──────────────────────┘  └─────────────────────────┘│
└────────────────┬────────────────────────────────────────┘
                 │
                 │ deploy-azure.sh reads & processes
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Terraform Variables (Environment)                      │
│  TF_VAR_azure_caddyfile_content                        │
│  TF_VAR_azure_wireguard_config                         │
└────────────────┬────────────────────────────────────────┘
                 │
                 │ Terraform passes to cloud-init
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Azure VM (cloud-init)                                  │
│  /etc/caddy/Caddyfile                                  │
│  /etc/wireguard/wg0.conf                               │
└─────────────────────────────────────────────────────────┘
```

## Template Variables

Templates use `{{VARIABLE_NAME}}` syntax. These are automatically replaced during deployment:

| Variable | Source | Example | Used In |
|----------|--------|---------|---------|
| `{{DOMAIN_NAME}}` | terraform.tfvars | `svc.example.com` | Caddyfile |
| `{{WIREGUARD_SERVER_IP}}` | terraform.tfvars | `10.0.0.1` | WireGuard |
| `{{WIREGUARD_CLIENT_IP}}` | terraform.tfvars | `10.0.0.2` | Both |
| `{{WIREGUARD_PORT}}` | terraform.tfvars | `51820` | WireGuard |
| `{{WIREGUARD_SERVER_PRIVATE_KEY}}` | Auto-generated | (secure key) | WireGuard |

## Workflows

### Initial Setup (One Time)

1. **Copy example templates:**
   ```bash
   cp -r azure-configs.example/ azure-configs/
   ```

2. **Add your home WireGuard public key:**
   ```bash
   # Get key from home server
   docker-compose exec wireguard cat /config/publickey
   
   # Edit template
   nano azure-configs/wg0-server.conf.template
   # Replace: PLACEHOLDER_HOME_PUBLIC_KEY with actual key
   ```

3. **Customize Caddyfile for your services:**
   ```bash
   nano azure-configs/Caddyfile.template
   # Add service blocks as needed
   ```

### Full Deployment (~10 minutes)

Use this for:
- First deployment
- Infrastructure changes (VM size, network, etc.)
- Major configuration overhauls

```bash
./scripts/deploy-azure.sh
```

**What happens:**
1. Reads templates from `azure-configs/`
2. Replaces `{{VARIABLES}}` with values from terraform.tfvars
3. Injects processed templates into cloud-init
4. Deploys/recreates Azure VM
5. VM boots and applies configuration

### Fast Caddy Update (~5 seconds)

Use this for:
- Adding new services to whitelist
- Changing reverse proxy settings
- Updating headers or security settings

```bash
# 1. Edit template
nano azure-configs/Caddyfile.template

# 2. Push update
./scripts/update-caddy-config.sh
```

**What happens:**
1. Reads template and processes variables
2. Validates syntax
3. SCPs to Azure VM
4. Backs up current config
5. Validates new config
6. Reloads Caddy (zero downtime)
7. Reverts on failure

### Fast WireGuard Update (~5 seconds)

Use this for:
- Changing peer AllowedIPs
- Updating PersistentKeepalive
- Adding new peers

```bash
# 1. Edit template
nano azure-configs/wg0-server.conf.template

# 2. Push update
./scripts/update-wireguard-peer.sh
```

**What happens:**
1. Reads template and processes variables
2. Preserves existing private key
3. SCPs to Azure VM
4. Backs up current config
5. Restarts WireGuard
6. Reverts on failure

## Troubleshooting

### Template variable not replaced

**Problem:** You see `{{DOMAIN_NAME}}` in deployed config

**Solution:** Check that deploy-azure.sh processed the template:
```bash
# Should show processed content without {{}}
echo $TF_VAR_azure_caddyfile_content
```

### Caddy validation fails

**Problem:** `update-caddy-config.sh` fails with validation error

**Solution:**
```bash
# Check syntax locally (if Caddy installed)
caddy validate --config azure-configs/Caddyfile.template

# Or SSH to VM and check logs
ssh admin@vm-ip 'sudo journalctl -u caddy -n 50'
```

### WireGuard won't start

**Problem:** WireGuard fails to start after update

**Solution:**
```bash
# SSH to VM and check config
ssh admin@vm-ip 'sudo cat /etc/wireguard/wg0.conf'

# Check WireGuard logs
ssh admin@vm-ip 'sudo journalctl -u wg-quick@wg0 -n 50'

# Restore backup if needed
ssh admin@vm-ip 'sudo cp /etc/wireguard/wg0.conf.backup /etc/wireguard/wg0.conf && sudo systemctl restart wg-quick@wg0'
```

### Home public key wrong

**Problem:** WireGuard has wrong home public key

**Solution:**
```bash
# Get correct key from home
docker-compose exec wireguard cat /config/publickey

# Update template
nano azure-configs/wg0-server.conf.template

# Redeploy or fast update
./scripts/update-wireguard-peer.sh
```

## Security Notes

- `azure-configs/` is gitignored to protect your home WireGuard public key
- Never commit actual keys or IP addresses
- Templates with placeholders are safe to commit to git
- Fast update scripts validate configs before applying

## Related Documentation

- [Main README](../README.md)
- [Azure Configs README](../azure-configs.example/README.md)
