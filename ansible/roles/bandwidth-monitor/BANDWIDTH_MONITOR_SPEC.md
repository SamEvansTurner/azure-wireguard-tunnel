# Azure WireGuard Bandwidth Monitoring - Specification

**Version**: 2.0  
**Date**: 2026-01-04  
**Status**: Implemented (Optional Feature)

## Overview

The bandwidth monitoring feature automatically monitors Azure spending and throttles Jellyfin streaming quality to stay within budget. This prevents unexpected bandwidth charges while maintaining service availability.

**Key Point**: This feature is **optional** and disabled by default. Enable it in `config.yml` if you want automatic bandwidth throttling.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│ Azure VM                                            │
│                                                     │
│  ┌────────────────────────────────────────────────┐ │
│  │ Bandwidth Monitor (Python + systemd timer)     │ │
│  │ - Queries Azure Budget API (hourly)            │ │
│  │ - Falls back to configured budget              │ │
│  │ - Updates Jellyfin via API through tunnel      │ │
│  └────────────────────────────────────────────────┘ │
│         ↓                                           │
│  ┌──────────────────────────────────────┐           │
│  │ Jellyfin API Client                  │           │
│  │ - Sets MaxStreamingBitrate           │           │
│  └──────────────────────────────────────┘           │
│         ↓                                           │
│     WireGuard Tunnel (10.0.0.2)                     │
└─────────────────────────────────────────────────────┘
                       ↓
             WireGuard Tunnel
                       ↓
┌─────────────────────────────────────────────────────┐
│ Home Network (NO CHANGES REQUIRED)                  │
│  ┌────────────────────────────────────────────────┐ │
│  │ Jellyfin Server (10.0.0.2:8096)                │ │
│  │ - Receives API calls from Azure                │ │
│  │ - Transcodes according to bitrate limit        │ │
│  └────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Create an Azure Budget (Required)

The bandwidth monitor queries the Azure Budget API to determine spending limits. You must create a budget first:

**Via Azure CLI:**
```bash
az consumption budget create \
  --budget-name "Monthly-Bandwidth-Limit" \
  --amount 150 \
  --time-grain Monthly \
  --start-date "2026-01-01" \
  --end-date "2027-12-31" \
  --subscription <your-subscription-id>
```

**Via Azure Portal:**
1. Go to **Cost Management + Billing**
2. Navigate to **Budgets**
3. Click **+ Add**
4. Set:
   - Name: `Monthly-Bandwidth-Limit`
   - Amount: `150` (or your credit amount)
   - Reset period: Monthly
5. Save

### 2. VM Managed Identity Permissions

The VM's managed identity needs the **Cost Management Reader** role. **This is automatically configured by Terraform** - no manual setup required.

Terraform creates:
- **System-Assigned Managed Identity** on the VM
- **Role Assignment** granting "Cost Management Reader" to the VM identity

The subscription ID is auto-detected from your Azure login context and passed to Ansible automatically.

<details>
<summary>Manual setup (if needed)</summary>

If you need to configure manually:

```bash
# Get VM managed identity ID
VM_IDENTITY=$(az vm show \
  --resource-group rg-secure-tunnel \
  --name <vm-name> \
  --query identity.principalId -o tsv)

# Assign Cost Management Reader role
az role assignment create \
  --assignee $VM_IDENTITY \
  --role "Cost Management Reader" \
  --scope /subscriptions/<subscription-id>
```
</details>

### 3. Jellyfin API Key

Generate an API key in Jellyfin:
1. Go to **Dashboard** → **API Keys**
2. Click **Add**
3. Enter a name (e.g., "Bandwidth Monitor")
4. Copy the generated key

## Configuration

Enable bandwidth monitoring in `config.yml`:

```yaml
bandwidth_monitor:
  # Set to true to enable
  enabled: true
  
  # Azure Budget name to query
  azure_budget_name: "Monthly-Bandwidth-Limit"
  
  # Fallback if budget not found (USD)
  fallback_budget: 150.00
  
  # Throttling thresholds (% of budget used)
  # 3-tier system: high, medium, disabled
  thresholds:
    high: 50         # 0-50%: High quality (4 Mbps)
    disabled: 90     # Above 90%: Service disabled (50-90% = medium)
  
  # Bitrate limits (bps)
  limits:
    high: 4000000         # 4 Mbps (720p-1080p)
    medium: 2000000       # 2 Mbps (480p-720p)
    disabled: 0           # Service off

jellyfin:
  # Jellyfin subdomain (prepended to domain.name)
  # e.g., "jellyfin" → jellyfin.svc.example.com
  subdomain: "jellyfin"
  api_key: "your-jellyfin-api-key"
```

**Note:** The Jellyfin connection is derived automatically:
- **Host**: Uses `wireguard.client_ip` (WireGuard tunnel endpoint)
- **Port**: Uses `network.home_caddy_port` (home Caddy HTTP port)
- **Hostname**: `{jellyfin.subdomain}.{domain.name}` (sent as Host header for routing)

## How It Works

### Budget Detection

1. **Azure Budget API** (Primary)
   - Queries `/subscriptions/{id}/providers/Microsoft.Consumption/budgets`
   - Looks for budget matching `azure_budget_name`
   - Falls back to first available budget if named budget not found

2. **Fallback Configuration**
   - Uses `fallback_budget` value if API unavailable
   - Useful for testing or if VM identity not configured

### Spending Detection

- Queries Azure Cost Management API for current month spending
- Calculates percentage of budget used
- Runs hourly via systemd timer

### Throttling Logic

| Budget Used | Quality Level | Bitrate | Resolution |
|-------------|--------------|---------|------------|
| 0-50% | High | 4 Mbps | 720p-1080p |
| 50-75% | Medium | 2 Mbps | 480p-720p |
| > 75% | Disabled | 0 | Service off |

### Jellyfin Integration

- Updates `MaxStreamingBitrate` via Jellyfin API
- Connects via WireGuard tunnel to home Caddy
- Uses `Host` header for hostname-based routing (no DNS hairpin)
- Jellyfin handles transcoding automatically
- No changes required on home network

## Monitoring & Troubleshooting

### Check Status

```bash
ssh <admin>@<vm-ip>
sudo /opt/bandwidth-monitor/monitor-costs.py status
```

Output:
```json
{
  "azure_budget_name": "Monthly-Bandwidth-Limit",
  "fallback_budget": "$150.00",
  "current_cost": "$45.23",
  "budget_limit": "$150.00",
  "percentage": "30.2%",
  "bandwidth_limit": "high",
  "bitrate": "4.0 Mbps",
  "last_updated": "2026-01-04T03:00:00+00:00",
  "budget_source": "azure_budget_api",
  "jellyfin_host": "10.0.0.2",
  "jellyfin_port": 8080
}
```

### View Logs

```bash
# Monitor logs in real-time
sudo tail -f /var/log/bandwidth-monitor.log

# View systemd timer status
sudo systemctl status bandwidth-monitor.timer

# View journal logs
sudo journalctl -u bandwidth-monitor.service -f
```

### Manual Trigger

```bash
# Run check immediately
sudo /opt/bandwidth-monitor/monitor-costs.py
```

### Common Issues

**"No Azure Budgets found"**
- Create an Azure Budget (see Prerequisites)
- Or rely on `fallback_budget` configuration

**"Azure clients not available"**
- Ensure VM has managed identity enabled
- Assign "Cost Management Reader" role

**"Failed to update Jellyfin"**
- Verify Jellyfin is accessible at 10.0.0.2:8096
- Check WireGuard tunnel is up: `sudo wg show`
- Verify API key is correct

## Files

| File | Description |
|------|-------------|
| `/opt/bandwidth-monitor/monitor-costs.py` | Main monitoring script |
| `/opt/bandwidth-monitor/venv/` | Python virtual environment |
| `/var/lib/bandwidth-monitor/state.json` | Persistent state |
| `/var/log/bandwidth-monitor.log` | Log file |
| `/etc/systemd/system/bandwidth-monitor.service` | Systemd service |
| `/etc/systemd/system/bandwidth-monitor.timer` | Hourly timer |

## Disabling

To disable bandwidth monitoring:

1. Set `bandwidth_monitor.enabled: false` in `config.yml`
2. Re-run: `./scripts/deploy.sh --ansible`

Or manually on the VM:
```bash
sudo systemctl stop bandwidth-monitor.timer
sudo systemctl disable bandwidth-monitor.timer
```

## Cost Estimate

Without bandwidth monitoring, unrestricted streaming could cost:
- 4 Mbps × 24 hours × 30 days = 1.3 TB/month
- 1.3 TB × $0.087/GB = **~$113/month** in bandwidth charges

With bandwidth monitoring enabled:
- Automatic throttling keeps costs within your Azure credit
- Graceful degradation of quality rather than service outage
- At 50% budget, drops to 2 Mbps (~$56/month if constant)
- At 75% budget, service disabled to prevent overage
