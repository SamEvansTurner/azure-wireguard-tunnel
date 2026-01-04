# Azure WireGuard Secure Tunnel

A solution for securely accessing home services remotely using Azure, WireGuard, and Caddy. Deploy a secure tunnel without exposing any ports on your home network, with full Infrastructure as Code.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Ansible](https://img.shields.io/badge/Ansible-%231A1918.svg?logo=ansible&logoColor=white)](https://www.ansible.com/)
[![Docker](https://img.shields.io/badge/Docker-%230db7ed.svg?logo=docker&logoColor=white)](https://www.docker.com/)

## 🎯 What This Solves

**Problem:** You want to access your home services (Jellyfin, Sonarr, etc.) from anywhere, but:
- Don't want to expose ports on your home network (security risk)
- Don't want to deal with dynamic DNS and port forwarding
- Want to stream media without TOS restrictions (Cloudflare Tunnel blocks this)

**Solution:** This project creates an encrypted WireGuard tunnel from your home network to an Azure VM. Internet traffic hits Azure (with your SSL certificates), gets reverse-proxied through the tunnel to your home services.

## ✨ Key Features

- ✅ **Zero exposed home ports** - Outbound tunnel only, no port forwarding needed
- ✅ **Your own domain** - Uses your Let's Encrypt wildcard certificate
- ✅ **No client software** - Access via regular HTTPS in any browser
- ✅ **Single configuration file** - All settings in one `config.yml`
- ✅ **One-command deployment** - `./scripts/deploy.sh` handles everything
- ✅ **Infrastructure as Code** - Terraform + Ansible automation
- ✅ **Automatic DNS updates** - VM updates DNS on boot via deSEC API
- ✅ **Optional bandwidth monitoring** - Auto-throttle based on Azure spending
- ✅ **No streaming restrictions** - Unlike Cloudflare Tunnel

## 🏗️ Architecture

```
[Internet User]
    ↓ HTTPS (jellyfin.svc.example.com)
    
[Azure VM - Your Region]
├─ Ubuntu 24.04 (B1ls: 1 vCPU, 512 MB RAM)
├─ Caddy: HTTPS termination + reverse proxy
│   └─ Your wildcard certificate (*.svc.example.com)
├─ WireGuard Server: Tunnel endpoint (10.0.0.1)
├─ deSEC DNS updater: Auto-updates A records on boot
├─ Security: NSG, UFW, Fail2Ban, SSH hardening
└─ [Optional] Bandwidth Monitor: Cost-based throttling
    ↓
    | WireGuard Encrypted Tunnel
    | (Outbound from home - no port forwarding!)
    ↓
[Home Network]
├─ Docker Compose Stack:
│   ├─ WireGuard Client (10.0.0.2)
│   ├─ Caddy: Routes to local services
│   └─ Cert-Sync: Auto-syncs certificates to Azure
└─ Your Services:
    ├─ Jellyfin (media streaming)
    ├─ Sonarr, Radarr (media management)
    └─ Any other Docker/local services
```

## 📋 Prerequisites

### Required Infrastructure

1. **Azure Account**
   - Free tier works initially
   - Azure CLI installed and authenticated (`az login`)

2. **Your Own Domain & DNS**
   - Domain registered and owned by you (any registrar)
   - **External DNS managed by [deSEC.io](https://desec.io)** (free, required for API)
   - deSEC API token for automated DNS updates
   - **Split DNS recommended** - Configure internal DNS (Pi-hole, AdGuard Home, router) to resolve `*.svc.example.com` to your home server for faster local access

3. **Certificate Management**
   - Wildcard certificate for `*.svc.example.com` 
   - Auto-renewal system required (Certbot, Caddy, etc.)
   - Certificates accessible for sync to Azure
   - **Recommended:** Since this project uses deSEC for DNS, you can use [docker-desec-certbot](https://github.com/SamEvansTurner/docker-desec-certbot) - a Docker container that automates wildcard certificate renewal with deSEC + Certbot integration

4. **Home Server**
   - Linux-based (or Docker-capable NAS)
   - **WireGuard Client and Caddy already configured** (typically via Docker)
   - Hosts services to access
   - Outbound internet connection (no port forwarding needed) - **📚 See [Quick Start Part 1](#part-1-configure-home-services-first)** for example setups
   - Split-DNS setup strongly recommended

5. **Tools**
   - **Linux/macOS or WSL** - Scripts require Linux environment
   - Terraform (>= 1.0)
   - Ansible (>= 2.9)
   - Python 3 (PyEnv and requirements will be created/installed)
   - SSH client

### Domain & Certificate Structure

This project uses a **subdomain for services** pattern:

```
Base Domain:        example.com
Service Domain:     svc.example.com
Wildcard Pattern:   *.svc.example.com
```

**Certificate Required:**
- Single wildcard certificate: `*.svc.example.com`
- Covers all services: `jellyfin.svc.example.com`, `sonarr.svc.example.com`, etc.

**Why this structure?**
- ✅ One certificate covers unlimited services
- ✅ Easy to add new services (no cert changes)
- ✅ Clean DNS organization
- ✅ Separates services from main domain

### Automatic Features

Once configured, the system handles:
- ✅ **DNS updates** - VM auto-updates A records on boot (via deSEC API)
- ✅ **Certificate sync** - Automated via Docker container
- ✅ **Security updates** - Unattended-upgrades on Azure VM
- ✅ **WireGuard keepalive** - Maintains tunnel connection

## 🚀 Quick Start

### Part 1: Configure Home Services First

Your home network requires two key components running before Azure deployment (plus one recommended component):

#### Required Services

**1. WireGuard Client**
- Creates the encrypted tunnel to Azure (outbound connection)
- Assigned IP: `10.0.0.2` (or your chosen client IP)
- Connects to Azure's WireGuard server after deployment
- Generate keys inside your WireGuard container: `wg genkey | tee privatekey | wg pubkey > publickey`

**2. Caddy Reverse Proxy**
- Routes incoming requests to your local services
- Handles service-to-container mapping (e.g., `jellyfin.svc.example.com` → `http://jellyfin:8096`)
- Split DNS Recommended to avoid all local traffic being routed through the tunnel

**3. Certificate Sync (Optional)**
- Automatically syncs renewed certificates to Azure
- Runs continuously, monitors for certificate changes
- Pre-built image: `ghcr.io/samevansturner/azure-wireguard-certsync:latest`

#### Example Configuration

This repository includes a Docker Compose example in **`home-configs/docker-compose.yml`** demonstrating:
- WireGuard client container setup
- Caddy reverse proxy configuration
- Certificate sync integration (optional)

Additionally, there are example Wireguard Client and Caddy configs in **`home-configs/wireguard`** and **`home-configs/caddy`** respectively.

**Use these examples as a reference** to configure your own infrastructure, or adapt them directly if they fit your setup.

📚 **Additional Resources:**
- [Caddy Documentation](https://caddyserver.com/docs/) - Reverse proxy configuration guide
- [WireGuard Docker Image](https://github.com/linuxserver/docker-wireguard) - Container setup details

#### Key Configuration Points

Before Azure deployment, ensure you have:
- ✅ WireGuard keys generated for your home client
- ✅ Caddy configured to route your services
- ✅ Wildcard certificate accessible (for use in Azure Caddy)

### Part 2: Deploy Azure Infrastructure

#### 2.1 Create Configuration File

```bash
# Copy the example configuration
cp config.yml.example config.yml

# Edit with your settings
nano config.yml
```

**Key settings to configure:**

```yaml
# Azure settings
azure:
  subscription_id: ""  # Auto-detected from Azure login
  location: "australiaeast"

# SSH access
ssh:
  admin_username: "yourusername"
  public_key_path: "~/.ssh/id_ed25519.pub"
  allowed_ipv4: "203.0.113.1/32"  # Your home IP

# Domain configuration
domain:
  name: "svc.example.com"
  desec_token: "your-desec-token"

# WireGuard
wireguard:
  port: 51820
  server_ip: "10.0.0.1"
  client_ip: "10.0.0.2"
  client_public_key: ""  # Add after home setup
```

📚 **Full configuration reference:** See comments in `config.yml.example`

#### 2.2 Deploy Everything

```bash
# Full deployment (Terraform + Ansible)
./scripts/deploy.sh

# This will:
# 1. Validate your configuration
# 2. Create Azure infrastructure (Terraform)
# 3. Configure the VM (Ansible)
# 4. Output connection details
```

**Save the output!** You'll need:
- Azure VM public IP
- Azure WireGuard public key

#### 2.3 Connect Home to Azure

Update your home WireGuard configuration with Azure details:

```ini
[Peer]
PublicKey = <Azure WireGuard public key from deployment>
Endpoint = <Azure VM IP>:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25
```

Restart WireGuard and verify:
```bash
wg show
# Should show handshake and data transfer
```

#### 2.4 Post-Deployment Status

After deployment completes, the Azure VM has the following status:

**✅ Already Running:**
- **WireGuard server** (`wg-quick@wg0`) - Started automatically on boot
- **Fail2Ban** - Protecting SSH access
- **UFW firewall** - Configured and enabled
- **DNS update service** - Runs on boot to update deSEC records
- **Certificate watcher** - Monitoring for certificate uploads

**⚠️ Requires Manual Steps:**
- **Caddy reverse proxy** - Enabled but NOT started
  - Waiting for SSL certificates to be synced
  - Will be started in Part 3 after certificate sync

**Why Caddy isn't auto-started:**
- Caddy requires valid SSL certificates (`fullchain.pem` and `privkey.pem`) in `/etc/caddy/certs/`
- Attempting to start without certificates will fail
- Certificates are synced in Part 3, then Caddy is started

**Next Steps:**
1. Continue to Part 3 to sync certificates
2. Start Caddy service after certificates are present
3. Validate everything works

### Part 3: Certificate Sync

#### 3.1.1 Set Up Automated Certificate Sync (option 1)

The cert-sync container is pre-built and available at `ghcr.io/samevansturner/azure-wireguard-certsync:latest`.

**For more detailed setup:** See [docs/CERTSYNC-DOCKER-SETUP.md](docs/CERTSYNC-DOCKER-SETUP.md)

**Generate and install SSH key for cert-sync:**

```bash
# Generate SSH key for cert-sync
ssh-keygen -t ed25519 -f ~/.ssh/certsync_ed25519 -C "cert-sync" -N ""

# Install key on Azure VM
cat ~/.ssh/certsync_ed25519.pub | ssh yourusername@<azure-vm-ip> \
  "sudo mkdir -p /home/certsync/.ssh && \
   sudo tee /home/certsync/.ssh/authorized_keys > /dev/null && \
   sudo chmod 700 /home/certsync/.ssh && \
   sudo chmod 600 /home/certsync/.ssh/authorized_keys && \
   sudo chown -R certsync:certsync /home/certsync/.ssh"

# Test the connection
ssh -i ~/.ssh/certsync_ed25519 certsync@<azure-vm-ip>
# Expected output:
# PTY allocation request failed on channel 0
# This service allows sftp connections only.
# Connection to <azure-vm-ip> closed.
# This confirms the key works! The user is restricted to SFTP for security.
```

**Run cert-sync container:**

EXAMPLE:
```bash
docker run -d \
  --name azure-cert-sync \
  --restart unless-stopped \
  -e DOMAIN="*.svc.example.com" \
  -v /path/to/certs:/certs:ro \
  -v ~/.ssh/certsync_ed25519:/ssh-key/id_ed25519:ro \
  ghcr.io/samevansturner/azure-wireguard-certsync:latest
```

**Features:**
- ✅ Monitors certificates for changes
- ✅ Automatically syncs when certs renew
- ✅ Runs continuously (no external cron needed)
- ✅ Secure (dedicated SSH key, limited permissions)

**📚 Detailed Setup:** See [docs/CERTSYNC-DOCKER-SETUP.md](docs/CERTSYNC-DOCKER-SETUP.md)

#### 3.1.2 Manual Certificate Sync (Alternative)

If you prefer not to use the automated cert-sync container, you can manually copy certificates to Azure:

**One-time setup:**

```bash
# Generate SSH key for manual cert sync (if not already done)
ssh-keygen -t ed25519 -f ~/.ssh/certsync_ed25519 -C "cert-sync" -N ""

# Install the public key on Azure VM
cat ~/.ssh/certsync_ed25519.pub | ssh yourusername@<azure-vm-ip> \
  "sudo mkdir -p /home/certsync/.ssh && \
   sudo tee /home/certsync/.ssh/authorized_keys > /dev/null && \
   sudo chmod 700 /home/certsync/.ssh && \
   sudo chmod 600 /home/certsync/.ssh/authorized_keys && \
   sudo chown -R certsync:certsync /home/certsync/.ssh"
```

**Manual sync (run whenever certificates renew):**

```bash
# Option 1: Using the provided script (handles naming automatically)
./scripts/sync-certs.sh [path-to-cert-directory]

# Option 2: Manual scp (must name files correctly)
# Certificate files MUST be named: svc.example.com.crt and svc.example.com.key
# (replace svc.example.com with your actual domain)
scp -i ~/.ssh/certsync_ed25519 \
  /path/to/svc.example.com.crt \
  /path/to/svc.example.com.key \
  certsync@<azure-vm-ip>:/home/certsync/incoming/
```

**Important:** Certificate files must be named exactly as your domain (e.g., `svc.example.com.crt` and `svc.example.com.key`). The automated cert-sync container and `sync-certs.sh` script handle this naming automatically, but with manual `scp` you must rename them yourself.

The systemd watcher will automatically process uploaded certificates and reload Caddy.

**Note:** With manual sync, you'll need to remember to copy certificates after each renewal (typically every 90 days for Let's Encrypt).

#### 3.2 Start Caddy Service

After certificates are synced to Azure using the certsync process, the caddy service will start automatically.

#### 3.3 Validate Everything Works

```bash
# Run full validation
./scripts/validate.sh

# Test from an external network
curl -I https://jellyfin.svc.example.com
# Should return: HTTP/2 200

# Check from a browser
# Visit: https://jellyfin.svc.example.com
```

**Total setup time: 30-60 minutes**

## ⚙️ Unified Configuration

All settings are managed through a single file: `config.yml`

### How It Works

```
config.yml (Single Source of Truth)
       │
       └─── ./scripts/deploy.sh
                   │
                   ├─── Generates terraform.tfvars
                   ├─── Runs Terraform (Azure infrastructure)
                   ├─── Generates Ansible inventory
                   └─── Runs Ansible (VM configuration)
```

### Configuration Sections

| Section | Description |
|---------|-------------|
| `azure` | Subscription, location, VM size |
| `ssh` | Admin username, SSH key paths, allowed IPs |
| `domain` | Domain name, deSEC token |
| `wireguard` | Tunnel port and IPs |
| `network` | VNet and subnet settings |
| `bandwidth_monitor` | Optional cost-based throttling |
| `jellyfin` | Jellyfin API settings (if bandwidth monitor enabled) |
| `tags` | Azure resource tags |

### Deployment Options

```bash
# Full deployment
./scripts/deploy.sh

# Plan only (preview changes)
./scripts/deploy.sh --plan

# Ansible only (skip Terraform)
./scripts/deploy.sh --ansible

# Destroy infrastructure
./scripts/deploy.sh --destroy
```

## 📊 Bandwidth Monitoring (Optional)

Automatically throttle Jellyfin streaming based on Azure spending to stay within budget.

### Prerequisites

1. **Create an Azure Budget:**
   ```bash
   az consumption budget create \
     --budget-name "Monthly-Bandwidth-Limit" \
     --amount 150 \
     --time-grain Monthly \
     --start-date "2026-01-01" \
     --end-date "2027-12-31"
   ```

2. **Enable in config.yml:**
   ```yaml
   bandwidth_monitor:
     enabled: true
     azure_budget_name: "Monthly-Bandwidth-Limit"
     fallback_budget: 150.00

   jellyfin:
    subdomain: "jellyfin"
    api_key: "your-api-key"
   ```

3. **Re-deploy:**
   ```bash
   ./scripts/deploy.sh --ansible
   ```

### How It Works

| Budget Used | Quality | Bitrate |
|-------------|---------|---------|
| < 50% | Full (1080p-4K) | 20 Mbps |
| 50-75% | Medium (720p) | 3 Mbps |
| 75-90% | Low (480p) | 1 Mbps |
| > 90% | Disabled | 0 |

📚 **Full details:** See [ansible/BANDWIDTH_MONITOR_SPEC.md](ansible/BANDWIDTH_MONITOR_SPEC.md)

## 🔐 Security Model

### 8 Layers of Defense

1. **Azure NSG** - Cloud network firewall
2. **UFW** - Host-level firewall
3. **Fail2Ban** - Brute-force protection
4. **SSH Hardening** - Key-only auth, no root
5. **WireGuard** - ChaCha20-Poly1305 encryption
6. **Caddy Headers** - HSTS, CSP, X-Frame-Options
7. **Home IP Whitelist** - Optional Caddy restriction
8. **OS Hardening** - Kernel tuning, auto-updates

### No Exposed Home Ports

- ✅ No port forwarding required
- ✅ No firewall changes needed
- ✅ Home network remains fully protected

## 🔧 Management & Maintenance

### Update Configuration

```bash
# Edit config.yml, then:
./scripts/deploy.sh --ansible
```

### Check Status

```bash
# SSH to VM
ssh yourusername@<azure-vm-ip>

# Check services
sudo systemctl status caddy wireguard-wg0
sudo wg show

# Check bandwidth monitor (if enabled)
sudo /opt/bandwidth-monitor/monitor-costs.py status
```

### Troubleshooting

**Tunnel won't connect:**
```bash
wg show  # Check both ends
# Verify IPs, keys, and UDP 51820 is open
```

**Can't access services:**
```bash
ssh yourusername@<azure-ip>
curl http://10.0.0.2:80 -H "Host: jellyfin.svc.example.com"
sudo systemctl status caddy
```

**DNS not updating:**
```bash
ssh yourusername@<azure-ip> 'sudo journalctl -u dns-update -n 50'
```

## 📚 Documentation

## 📚 Additional Documentation

- **[Certificate Sync Setup](docs/CERTSYNC-DOCKER-SETUP.md)** - Automated cert management

## 💡 Comparison with Alternatives

| Feature | This Project | Cloudflare Tunnel | Tailscale |
|---------|--------------|-------------------|-----------|
| Media streaming | ✅ Unrestricted | ❌ Against TOS | ✅ Yes |
| No client software | ✅ Browser only | ✅ Browser only | ❌ Needs client |
| Your own domain | ✅ Yes | ⚠️ Shared | ❌ No |
| Port forwarding | ✅ Not needed | ✅ Not needed | ✅ Not needed |
| Cost | ~$10/month | Free | Free-$5/mo |
| Privacy | ✅ Full control | ⚠️ Cloudflare sees traffic | ⚠️ Relay |

## 🤝 Contributing

Contributions welcome! Areas of interest:
- Report issues or bugs
- Additional bandwidth control targets (beyond Jellyfin)
- Enhance security features
- Optimize costs further

## 📝 License

MIT License - See [LICENSE](LICENSE) file.
