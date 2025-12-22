# Azure Configuration Templates

This directory contains templates for Azure VM configuration files that get deployed via cloud-init.

## Files

- **`Caddyfile.template`** - Azure Caddy reverse proxy configuration (service whitelist)
- **`wg0-server.conf.template`** - Azure WireGuard server configuration

## Setup (First Time)

1. **Copy this directory to `azure-configs/`:**
   ```bash
   cp -r azure-configs.example/ azure-configs/
   ```

2. **Edit WireGuard template with your home public key:**
   ```bash
   nano azure-configs/wg0-server.conf.template
   ```
   
   Replace `PLACEHOLDER_HOME_PUBLIC_KEY` with your actual home WireGuard public key.
   
   Get it from your home server:
   ```bash
   # On home server, inside wireguard container
   cat /config/publickey
   ```

3. **Customize Caddyfile for your services:**
   ```bash
   nano azure-configs/Caddyfile.template
   ```
   
   Add/remove service blocks as needed. Commented examples are provided.

## Template Variables

Templates use `{{VARIABLE_NAME}}` syntax. These are automatically replaced during deployment:

| Variable | Source | Description |
|----------|--------|-------------|
| `{{DOMAIN_NAME}}` | terraform.tfvars | Your domain (e.g., svc.example.com) |
| `{{WIREGUARD_SERVER_IP}}` | terraform.tfvars | Azure WG IP (e.g., 10.0.0.1) |
| `{{WIREGUARD_CLIENT_IP}}` | terraform.tfvars | Home WG IP (e.g., 10.0.0.2) |
| `{{WIREGUARD_PORT}}` | terraform.tfvars | WG UDP port (default: 51820) |
| `{{WIREGUARD_SERVER_PRIVATE_KEY}}` | Auto-generated | Azure WG private key (generated during deployment) |

**Note:** Home WireGuard public key is **NOT** a template variable - you must manually paste your actual key into the template.

## Deployment

### Full Deployment - Including infrastructure
```bash
./scripts/deploy-azure.sh
```

This reads your templates, replaces variables, and deploys the Azure VM.

### Fast Config Updates (No VM Recreation)

**Update Caddy (add/remove services):**
```bash
# 1. Edit template
nano azure-configs/Caddyfile.template

# 2. Push update
./scripts/update-caddy-config.sh
```

**Update WireGuard peer:**
```bash
# 1. Edit template
nano azure-configs/wg0-server.conf.template

# 2. Push update
./scripts/update-wireguard-peer.sh
```

## Tips

- Keep commented examples in Caddyfile for quick reference
- Test service additions with `update-caddy-config.sh` before committing
- Back up your `azure-configs/` directory (it contains your home WG public key)
- Use `update-caddy-config.sh` for fast iterations during development

## Security Notes

- `azure-configs/` is gitignored to protect your home WireGuard public key
- Never commit actual keys or sensitive data
- The templates themselves (with placeholders) are safe to commit
