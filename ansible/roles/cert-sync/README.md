# Certificate Sync Role

This Ansible role sets up automatic SSL certificate synchronization from a home server to the Azure VM.

## Overview

The cert-sync role creates:
- A restricted `certsync` user for SFTP-only access
- A systemd path watcher that monitors for uploaded certificates
- A processor service that validates and installs certificates
- Automatic Caddy reload when certificates are updated

## How It Works

```
Home Server                    Azure VM
    |                              |
    |  SFTP Upload                 |
    +----------------------------->+
    |  (via certsync user)         |
    |                              |
    |                              v
    |                    /home/certsync/incoming/
    |                              |
    |                    (systemd path watcher detects change)
    |                              |
    |                              v
    |                    /usr/local/bin/process-certs.sh
    |                              |
    |                    - Validates certificate files
    |                    - Backs up existing certs
    |                    - Copies to /etc/caddy/certs/
    |                    - Sets correct permissions
    |                    - Reloads Caddy
    |                              |
    |                              v
    |                    Caddy serves with new certs
```

## Files Created

| Path | Purpose |
|------|---------|
| `/home/certsync/` | Home directory for certsync user |
| `/home/certsync/incoming/` | Upload directory (monitored) |
| `/home/certsync/.ssh/authorized_keys` | SSH public key for authentication |
| `/etc/caddy/certs/` | Final certificate location |
| `/usr/local/bin/process-certs.sh` | Certificate processing script |

## Systemd Units

| Unit | Purpose |
|------|---------|
| `certsync-watcher.path` | Monitors `/home/certsync/incoming/` for changes |
| `certsync-processor.service` | Processes uploaded certificates |

## Configuration

In `config.yml`:

```yaml
cert_sync:
  certsync_ssh_public_key: "ssh-ed25519 AAAA... your-key"
```

## Usage

### Uploading Certificates

From your home server:

```bash
sftp certsync@your-azure-vm
put /path/to/fullchain.pem incoming/
put /path/to/privkey.pem incoming/
quit
```

Or using the Docker-based sync script:

```bash
./scripts/sync-certs.sh
```

### Monitoring

Check certificate processing status:

```bash
# View processor logs
journalctl -u certsync-processor.service

# Check path watcher status
systemctl status certsync-watcher.path

# View current certificates
ls -la /etc/caddy/certs/
```

### Manual Trigger

If you need to manually trigger certificate processing:

```bash
sudo systemctl start certsync-processor.service
```

## Security

- `certsync` user has **SFTP-only** access (no shell)
- Upload directory has restricted permissions (700)
- Certificates are validated before installation
- Old certificates are backed up (last 5 kept)
- Processing runs with minimal privileges via systemd hardening

## Troubleshooting

### Certificates not being processed

1. Check the path watcher is running:
   ```bash
   systemctl status certsync-watcher.path
   ```

2. Check for processing errors:
   ```bash
   journalctl -u certsync-processor.service -n 50
   ```

3. Verify file permissions:
   ```bash
   ls -la /home/certsync/incoming/
   ```

### Permission denied on upload

1. Verify SSH key is correctly configured:
   ```bash
   cat /home/certsync/.ssh/authorized_keys
   ```

2. Check SSH config allows certsync user:
   ```bash
   grep -A5 "Match User certsync" /etc/ssh/sshd_config.d/*
   ```

### Caddy not using new certificates

1. Check Caddyfile references correct cert path:
   ```bash
   grep -r "tls" /etc/caddy/Caddyfile
   ```

2. Manually reload Caddy:
   ```bash
   sudo systemctl reload caddy
