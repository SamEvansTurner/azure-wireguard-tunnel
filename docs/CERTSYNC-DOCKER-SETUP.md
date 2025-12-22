# Certificate Sync - Docker Setup Guide

Automated certificate synchronization from any Docker host to your Azure WireGuard VM using a self-scheduling container.

## Overview

The certificate sync system uses:
- **Long-running Docker container** (self-scheduling, no external cron needed)
- **Dedicated SSH key** for security (separate from admin access)
- **Change detection** (only syncs when certificates actually change)
- **Systemd automation** on Azure VM to process certificates
- **Works on any platform** that runs Docker containers

## Prerequisites

- Docker installed on your certificate host
- Let's Encrypt certificates (or any SSL certificates)
- Azure WireGuard VM deployed (see main README)
- SSH access to Azure VM

---

## Part 1: Generate SSH Key for Certificate Sync

On your Docker host (the machine with certificates):

```bash
# Create SSH directory if it doesn't exist
mkdir -p ~/.ssh

# Generate ED25519 key (recommended)
ssh-keygen -t ed25519 -f ~/.ssh/certsync_ed25519 -C "certsync@$(hostname)" -N ""

# View the public key (you'll need this in Part 2)
cat ~/.ssh/certsync_ed25519.pub
```

**Save this public key** - you'll add it to your Azure VM in the next step.

---

## Part 2: Configure Azure VM to Accept Certificate Uploads

Add the SSH public key to the certsync user:

```bash
# Upload and install the key automatically
cat ~/.ssh/certsync_ed25519.pub | ssh yourusername@<azure-vm-ip> \
  "sudo mkdir -p /home/certsync/.ssh && \
   sudo tee /home/certsync/.ssh/authorized_keys > /dev/null && \
   sudo chmod 700 /home/certsync/.ssh && \
   sudo chmod 600 /home/certsync/.ssh/authorized_keys && \
   sudo chown -R certsync:certsync /home/certsync/.ssh"

```

Test the connection from your Docker host:

```bash
# Test the connection
ssh -i ~/.ssh/certsync_ed25519 certsync@<azure-vm-ip>
# Expected output:
# PTY allocation request failed on channel 0
# This service allows sftp connections only.
# Connection to <azure-vm-ip> closed.
# This confirms the key works! The user is restricted to SFTP for security.
```

You should see "This account is currently not available" - that's correct! The user has no shell for security.

---

## Part 3: Run the Docker Container

### Option A: Docker Run (Universal)

```bash
docker run -d \
  --name azure-cert-sync \
  --restart unless-stopped \
  -e DOMAIN="svc.example.com" \
  -e SSH_KEY_PATH="/ssh-key/id_ed25519" \
  -e SYNC_INTERVAL="86400" \
  -v /path/to/your/certs:/certs:ro \
  -v ~/.ssh/certsync_ed25519:/ssh-key/id_ed25519:ro \
  ghcr.io/samevansturner/azure-wireguard-certsync:latest
```

**Note:** Container runs as root for maximum compatibility. All volumes should be mounted read-only (`:ro`) for security.

**Environment Variables:**

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `VM_IP` | No | Auto-resolves via DNS | Azure VM IP (optional, auto-resolves from `lookup.${DOMAIN}` via public DNS if not set) |
| `DOMAIN` | Yes | - | Domain name (without wildcard e.g., `svc.example.com`) |
| `SSH_KEY_PATH` | Yes | - | Path to SSH key inside container |
| `SYNC_INTERVAL` | No | `86400` | Seconds between checks (24 hours) |
| `CERTSYNC_USER` | No | `certsync` | SSH username on Azure VM |

**DNS-based IP Resolution:**
The container can automatically resolve your Azure VM IP using public DNS (Cloudflare 1.1.1.1), bypassing split DNS. It queries `lookup.${DOMAIN}` to get the IP. This means you don't need to update the container when your Azure IP changes - it will automatically detect the new IP on the next sync cycle.

To explicitly set the IP (useful for troubleshooting), add: `-e VM_IP="20.123.45.67"`

**Volume Mounts:**

| Host Path | Container Path | Mode | Description |
|-----------|----------------|------|-------------|
| `/path/to/certs` | `/certs` | Read-only | Your Let's Encrypt certificates |
| `~/.ssh/certsync_ed25519` | `/ssh-key/id_ed25519` | Read-only | SSH private key |

**Common Sync Intervals:**
- `3600` = 1 hour
- `21600` = 6 hours
- `86400` = 24 hours (default)
- `604800` = 7 days

### Option B: Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  azure-cert-sync:
    image: ghcr.io/samevansturner/azure-wireguard-certsync:latest
    container_name: azure-cert-sync
    restart: unless-stopped
    environment:
      - DOMAIN=*.yourdomain.com
      - SSH_KEY_PATH=/ssh-key/id_ed25519
      - SYNC_INTERVAL=86400
    volumes:
      - /path/to/your/certs:/certs:ro
      - ~/.ssh/certsync_ed25519:/ssh-key/id_ed25519:ro
```

Start the container:

```bash
docker-compose up -d
```

---

## Part 4: Verify and Monitor

### Check Container Status

```bash
# View running containers
docker ps

# Follow logs in real-time
docker logs -f azure-cert-sync

# View last 50 lines
docker logs azure-cert-sync --tail 50
```

### Expected Log Output

**First run (always syncs):**
```
Certificate Sync Daemon Started
Sync interval: 86400 seconds (24 hours)

─────────────────────────────────────────────────────
Starting sync check at Sat Dec 28 17:00:00 UTC 2025

╔════════════════════════════════════════════════════╗
║     Certificate Sync to Azure VM (Container)      ║
╚════════════════════════════════════════════════════╝

Target: certsync@<ip>
Domain: *.yourdomain.com

✅ Found certificate: /certs/yourdomain.crt
✅ Certificate valid
🆕 First run - certificates will be synced
✅ SSH connection successful
✅ Certificates uploaded successfully

✓ Sync check complete

Sleeping for 86400 seconds...
Next check at Sun Dec 29 17:00:00 UTC 2025
```

**Subsequent run (no changes):**
```
Starting sync check at Sun Dec 29 17:00:00 UTC 2025

✓ Certificates unchanged, skipping sync

✓ Sync check complete
Sleeping for 86400 seconds...
```

**When certificates change:**
```
🔄 Certificate change detected - syncing to Azure
✅ Certificates uploaded successfully
```

### Verify on Azure VM

```bash
ssh your-admin@azure-vm-ip 'sudo journalctl -u certsync-processor -n 50'
```

### Manual Sync Trigger

If you need to force a sync immediately:

```bash
# Restart container (triggers first-run sync)
docker restart azure-cert-sync

# Or exec the sync script directly
docker exec azure-cert-sync /app/sync-certs.sh
```

---

## Container Behavior

### Change Detection

The container uses SHA256 checksums to detect certificate changes:
- **First run:** Always syncs (no stored checksums)
- **Subsequent runs:** Only syncs if checksums differ
- **Container restart:** Treated as first run (always syncs)

This minimizes unnecessary SSH connections and Azure VM load.

### Scheduling

The container runs continuously with an internal scheduler:
- Checks certificates every `SYNC_INTERVAL` seconds
- Syncs only if changed
- Sleeps until next interval
- Restarts automatically if crashed (with `--restart unless-stopped`)

No external cron or scheduler needed!

---

## Troubleshooting

### Container won't start

```bash
docker logs azure-cert-sync
```

**Common issues:**
- Missing environment variables
- SSH key not found at mount path
- Certificate directory not mounted

### SSH connection fails

```bash
# Test from Docker host
ssh -i ~/.ssh/certsync_ed25519 certsync@your-azure-vm-ip

# Verbose output
ssh -i ~/.ssh/certsync_ed25519 -v certsync@your-azure-vm-ip
```

**Check:**
- Public key is in `/home/certsync/.ssh/authorized_keys` on Azure VM
- Private key permissions: `chmod 600 ~/.ssh/certsync_ed25519`
- VM firewall allows SSH from your IP

### Certificates not found

```bash
# Check certificate directory
ls -la /path/to/your/certs

# Check inside container
docker exec azure-cert-sync ls -la /certs
```

**Supported formats:**
- `domain.crt` / `domain.key`
- `domain/fullchain.pem` / `domain/privkey.pem`

### View detailed sync logs

```bash
# Follow logs
docker logs -f azure-cert-sync

# Since specific time
docker logs azure-cert-sync --since 1h

# With timestamps
docker logs -t azure-cert-sync
```

---

## Security Best Practices

✅ **Do:**
- Use dedicated SSH key (separate from admin access)
- Mount SSH key as read-only
- Use strong key types (ED25519 or RSA 4096)
- Rotate keys periodically
- Monitor sync logs

❌ **Don't:**
- Share SSH keys across services
- Give certsync user sudo access
- Mount certificate directory as read-write
- Use weak SSH keys

---

## Related Documentation

- [Main README](../README.md)
