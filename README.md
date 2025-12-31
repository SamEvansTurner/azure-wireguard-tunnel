# Azure WireGuard Secure Tunnel

A solution for securely accessing home services remotely using Azure, WireGuard, and Caddy. Deploy a secure tunnel without exposing any ports on your home network, with full Infrastructure as Code.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Terraform](https://img.shields.io/badge/Terraform-%235835CC.svg?logo=terraform&logoColor=white)](https://www.terraform.io/)
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
- ✅ **Fast configuration updates** - Add services in 5 seconds (no VM recreation)
- ✅ **Template-based config** - Separate configs from infrastructure
- ✅ **Infrastructure as Code** - Fully automated with Terraform
- ✅ **Automatic DNS updates** - VM updates DNS on boot via deSEC API
- ✅ **No streaming restrictions** - Unlike Cloudflare Tunnel

## 🏗️ Architecture

```
[Internet User]
    ↓ HTTPS (jellyfin.svc.example.com)
    
[Azure VM - Your Region]
├─ Ubuntu Minimal 24.04 (B1ls: 1 vCPU, 512 MB RAM)
├─ Caddy: HTTPS termination + reverse proxy
│   └─ Your wildcard certificate (*.svc.example.com)
├─ WireGuard Server: Tunnel endpoint (10.0.0.1)
├─ deSEC DNS updater: Auto-updates A records on boot
└─ Security: NSG, UFW, Fail2Ban, SSH hardening
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
   - Pay-as-you-go for production use
   - Azure CLI installed and authenticated (`az login`)

2. **Your Own Domain & DNS**
   - Domain registered and owned by you (any registrar)
   - **External DNS managed by [deSEC.io](https://desec.io)** (free, required for API)
   - deSEC API token for automated DNS updates
   - **Split DNS recommended** - Configure internal DNS (Pi-hole, AdGuard Home, router) to resolve `*.svc.example.com` to your home server for faster local access

3. **Certificate Management**
   - Wildcard certificate for `*.svc.example.com` 
   - Auto-renewal system required (Certbot, Caddy, TrueNAS, etc.)
   - Certificates accessible for sync to Azure
   - **Recommended:** Since this project uses deSEC for DNS, you can use [docker-desec-certbot](https://github.com/SamEvansTurner/docker-desec-certbot) - a Docker container that automates wildcard certificate renewal with deSEC + Certbot integration

4. **Home Server**
   - Linux-based (or Docker-capable NAS)
   - **WireGuard Client and Caddy already configured** (typically via Docker)
   - Hosts services to access
   - Outbound internet connection (no port forwarding needed) - **📚 See [Quick Start Part 1](#part-1-configure-home-services-first)** for example setups
   - Split-DNS setup strongly recommended

5. **Tools**
   - **Linux/macOS or WSL** - Terraform and deployment scripts require a Linux environment (Windows users: install [WSL 2](https://docs.microsoft.com/en-us/windows/wsl/install))
   - Terraform (>= 1.0)
   - SSH client
   - Basic Linux/networking knowledge

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
- ✅ Caddy configured to route your services (Jellyfin, Sonarr, etc.)
- ✅ Wildcard certificate accessible (for Azure sync)
- ✅ Services accessible to Caddy (same Docker network or host networking)

### Part 2: Deploy Azure Tunnel

#### Prerequisites - Gather Required Information

Before deploying, collect the following information:

**1. SSH Key for Azure VM Access**
```bash
# Check if SSH key exists
ls ~/.ssh/id_ed25519.pub

# If not, generate one
ssh-keygen -t ed25519 -C "azure-vm-admin"
# Press Enter for default location
# Enter passphrase (optional but recommended)
```

**2. Your Home IP Address**
```bash
# IPv4 address (required)
curl -4 ifconfig.me

# IPv6 address (if available)
curl -6 ifconfig.me

# Save the IPv4 - you'll use it for allowed_ssh_ipv4 in terraform.tfvars
```

**3. deSEC API Token**
- Log in to [deSEC.io](https://desec.io)
- Navigate to **Token Management**
- Create a new token with **read/write** permissions
- Copy and save the token securely
- You'll use this for `desec_token` in terraform.tfvars

**Why these are needed:**
- ✅ **SSH key**: Secure access to Azure VM (password auth disabled)
- ✅ **Home IP**: Restricts SSH access to your network only
- ✅ **deSEC token**: Enables automatic DNS updates on VM boot

#### 2.1 Configure Azure Templates

```bash
# Copy example templates to working directory
cp -r azure-configs.example/ azure-configs/

# Edit WireGuard server template with your HOME public key
nano azure-configs/wg0-server.conf.template
# Replace PLACEHOLDER_HOME_PUBLIC_KEY with your home's WireGuard public key

# Customize Caddyfile for your services
nano azure-configs/Caddyfile.template
# Add service blocks matching your home Caddyfile, or at least for the services you wish to access remotely
```

**📚 Reference:** See `azure-configs.example/README.md` for template details

#### 2.2 Configure Terraform Variables

```bash
cd terraform

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your details
nano terraform.tfvars
```

**📚 Complete Variable Reference:** See [terraform/README.md](terraform/README.md) for detailed descriptions of all configuration options.

#### 2.3 Deploy Infrastructure

```bash
# From project root
./scripts/deploy-azure.sh

# This script will:
# 1. Validate all prerequisites
# 2. Process configuration templates
# 3. Deploy Azure infrastructure (5-10 minutes)
# 4. Output connection details and Azure WireGuard public key
```

**Save the output!** You'll need:
- Azure VM public IP
- Azure WireGuard public key

#### 2.4 Connect Home to Azure

Update your home WireGuard configuration:

```bash
# Edit home WireGuard config on home server

# Update with Azure details from deployment output:
[Peer]
PublicKey = <Azure WireGuard public key from deployment>
Endpoint = <Azure VM IP>:51820
AllowedIPs = 10.0.0.1/32
PersistentKeepalive = 25
```

Restart the wireguard client and test connectivity

```bash
# Verify tunnel is connected
wg show
# Should show handshake and data transfer
```

#### 2.5 Post-Deployment Status

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
# Generate SSH key (no passphrase for automation)
ssh-keygen -t ed25519 -f ~/.ssh/certsync_ed25519 -C "cert-sync" -N ""

# Upload and install the key automatically
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
  -e SSH_KEY_PATH="/ssh-key/id_ed25519" \
  -v /path/to/your/certificates:/certs:ro \
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

After certificates are synced to Azure, start the Caddy reverse proxy:

```bash
# SSH into Azure VM
ssh yourusername@<azure-vm-ip>

# Verify certificates are present
ls -l /etc/caddy/certs/
# Should show: {{DOMAIN}}.crt and {{DOMAIN}}.key

# Start Caddy
sudo systemctl start caddy

# Enable Caddy to start on boot (for future reboots)
sudo systemctl enable caddy

# Verify Caddy is running
sudo systemctl status caddy
```

**Note:** Once certificates are present and Caddy is enabled, it will start automatically on future reboots. You only need to manually start it this first time.

#### 3.3 Validate Everything Works

```bash
# Run full validation
./scripts/validate.sh

# Test accessing your service from an external IP
curl -I https://jellyfin.svc.example.com
# Should return: HTTP/2 200

# Check from a browser
# Visit: https://jellyfin.svc.example.com
```

**Total setup time: 30-60 minutes** (depending on familiarity)

## ⚡ Fast Configuration Updates

One of the key features of this project is the ability to update service configurations in seconds without recreating the Azure VM.

### Template System

Configuration is separated from infrastructure:
- **Templates:** `azure-configs/` (your working configs, gitignored)
- **Infrastructure:** `terraform/` (deployment code)
- **Home:** `home-configs/` (Docker Compose stack)

### Adding a New Service to the Tunnel Forward (5 seconds!)

```bash
# 1. Edit template
nano azure-configs/Caddyfile.template

# Add service block:
@radarr host radarr.{{DOMAIN_NAME}}
handle @radarr {
  reverse_proxy http://{{WIREGUARD_CLIENT_IP}}:80 {
    header_up Host {host}
  }
}

# 2. Push update to Azure
./scripts/update-caddy-config.sh

# Done! Service is live in ~5 seconds
```

**No VM recreation needed!** The update script:
- ✅ Processes templates
- ✅ Validates configuration
- ✅ SCPs to Azure
- ✅ Reloads Caddy (zero downtime)
- ✅ Automatically rolls back on failure

### Update Scripts

- `./scripts/update-caddy-config.sh` - Update reverse proxy (5 sec)
- `./scripts/update-wireguard-peer.sh` - Update WireGuard config (5 sec)
- `./scripts/deploy-azure.sh` - Full redeployment (10 min, for infrastructure changes)

**📚 Full Documentation:** See [docs/TEMPLATE-SYSTEM.md](docs/TEMPLATE-SYSTEM.md)

## 🔐 Security Model

### 8 Layers of Defense

1. **Azure NSG (Network Security Group)**
   - Firewall at cloud network edge
   - Only allows: HTTPS (443), SSH from your IP, WireGuard (51820)
   - Blocks all other inbound traffic

2. **UFW (Uncomplicated Firewall)**
   - Host-level firewall on Azure VM
   - Defense in depth (redundant with NSG)
   - Identical rules to NSG

3. **Fail2Ban**
   - Automatically bans IPs after failed SSH attempts
   - 3 failures = 1 hour ban
   - Protects against brute force

4. **SSH Hardening**
   - Public key authentication ONLY
   - Password authentication disabled
   - Root login disabled
   - No common usernames allowed

5. **WireGuard Encryption**
   - ChaCha20-Poly1305 encryption
   - Perfect forward secrecy
   - Minimal attack surface

6. **Caddy Security Headers**
   - HSTS (HTTP Strict Transport Security)
   - X-Content-Type-Options
   - X-Frame-Options
   - Referrer-Policy

7. **Home IP Whitelist (Optional)**
   - Caddy only accepts traffic from Azure
   - Additional layer if desired

8. **OS Hardening**
   - Kernel parameter tuning
   - Minimal installed packages
   - Automatic security updates
   - Log monitoring

### No Exposed Home Ports

The tunnel is **outbound only** from your home network:
- ✅ No port forwarding required
- ✅ No firewall changes needed
- ✅ Home network remains fully protected
- ✅ Even if Azure is compromised, home network is safe

### Certificate Security

- Certificates synced via SSH (encrypted in transit)
- Stored with restricted permissions on Azure
- Dedicated user (`certsync`) with no sudo access
- Systemd handles secure installation

## 📂 Project Structure

```
azure-wireguard-tunnel/
│
├── azure-configs.example/       # Example Azure config templates
│
├── home-configs/                # Home Docker stack examples
│   ├── docker-compose.yml       # Docker container setup examples
│   ├── caddy/                   # Caddy config examples
│   └── wireguard/               # Wireguard config examples
│
├── terraform/                   # Infrastructure as Code
│
├── cloud-init/                  # VM bootstrap
│   └── bootstrap.yml            # Automated VM setup - loaded from azure-configs + scripts/azure-vm
│
├── docker/                      # Cert-sync container
│
├── scripts/                     # Automation scripts
│   └── azure-vm/                # Azure VM scripts
│
├── docs/                        # Documentation
│   ├── TEMPLATE-SYSTEM.md       # Template system guide
│   └── CERTSYNC-DOCKER-SETUP.md # Cert sync setup
│
└── .github/workflows/           # CI/CD
```

## 🔧 Management & Maintenance

### Common Operations

**Manual certificate sync:**
```bash
# If automated sync isn't set up yet - this is useful when first deploying the azure VM
./scripts/sync-certs.sh
```

### Troubleshooting

**Tunnel won't connect:**
```bash
# Check WireGuard on both ends
wg show  # Home - inside docker container
ssh yourusername@<azure-ip> 'sudo wg show'  # Azure

# Verify IPs and keys match configuration
# Check firewall allows UDP 51820
```

**Can't access services:**
```bash
# Test from Azure VM
ssh yourusername@<azure-ip>
curl http://10.0.0.2:80 -H "Host: jellyfin.svc.example.com"

# Check Caddy is running
docker-compose ps  # Home
ssh yourusername@<azure-ip> 'systemctl status caddy'  # Azure
```

**DNS not updating:**
```bash
# Check DNS update service
ssh yourusername@<azure-ip> 'sudo journalctl -u dns-update -n 50'

# Manually trigger update
ssh yourusername@<azure-ip> 'sudo systemctl restart dns-update'

# Verify DNS
dig @1.1.1.1 jellyfin.svc.example.com
```

**📚 More troubleshooting:** See service logs and validate.sh output

## 📚 Additional Documentation

- **[Template System](docs/TEMPLATE-SYSTEM.md)** - Fast config updates
- **[Certificate Sync Setup](docs/CERTSYNC-DOCKER-SETUP.md)** - Automated cert management

## 💡 Comparison with Alternatives

| Feature | This Project | Cloudflare Tunnel | Tailscale | Traditional VPN |
|---------|--------------|-------------------|-----------|-----------------|
| Media streaming | ✅ Unrestricted | ❌ Against TOS | ✅ Yes | ✅ Yes |
| No client software | ✅ Browser only | ✅ Browser only | ❌ Needs client | ❌ Needs client |
| Your own domain | ✅ Yes | ⚠️ Shared | ❌ No | ⚠️ Complex |
| Port forwarding | ✅ Not needed | ✅ Not needed | ✅ Not needed | ❌ Required |
| Cost | ~$10/month | Free | Free-$5/mo | $5-15/mo |
| Privacy | ✅ Full control | ⚠️ Cloudflare sees traffic | ⚠️ Tailscale relay | ✅ Full control |
| Setup complexity | Medium | Easy | Easy | Complex |

**When to use alternatives:**
- Simple file access → Tailscale
- No media streaming → Cloudflare Tunnel
- Just need VPN → Traditional VPN service

## 🤝 Contributing

Contributions are welcome! This project is designed to be:
- **Educational** - Learn cloud infrastructure, IaC, networking
- **Customizable** - Fork and adapt for your needs

**Ways to contribute:**
- Report issues or bugs
- Improve documentation
- Add support for other cloud providers (AWS, GCP)
- Enhance security features
- Optimize costs further

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

Feel free to use this project for personal or commercial purposes. Attribution appreciated but not required.
