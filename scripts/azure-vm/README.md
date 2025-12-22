# Azure VM Scripts

This directory contains scripts that are deployed to and run on the Azure VM. These scripts are extracted from the cloud-init configuration for better maintainability.

## Scripts

### `process-certs.sh`

**Purpose:** Process uploaded SSL certificates for Caddy

**Deployed to:** `/usr/local/bin/process-certs.sh` on Azure VM

**Triggered by:** Systemd path watcher (`certsync-watcher.path`) when files appear in `/home/certsync/incoming/`

**What it does:**
1. Validates uploaded certificate and private key files
2. Backs up existing certificates (keeps last 5 backups)
3. Installs certificates to `/etc/caddy/certs/`
4. Sets correct ownership (`caddy:caddy`) and permissions
5. Reloads Caddy to apply new certificates
6. Cleans up incoming directory

**Template Variables:**
- `${domain_name}` - The domain name for certificates (e.g., `*.yourdomain.com`)

**Deployment via Terraform templatefile():**

In `terraform/main.tf`:
```hcl
# Load and render the process-certs script
data "template_file" "process_certs_script" {
  template = file("${path.module}/../scripts/azure-vm/process-certs.sh")
  
  vars = {
    domain_name = var.domain_name
  }
}

# Inject rendered script into cloud-init
data "template_file" "cloud_init" {
  template = file("${path.module}/../cloud-init/bootstrap.yml")
  
  vars = {
    process_certs_script = data.template_file.process_certs_script.rendered
    # ... other variables
  }
}
```

In `cloud-init/bootstrap.yml`:
```yaml
write_files:
  - path: /usr/local/bin/process-certs.sh
    permissions: '0755'
    content: |
      ${process_certs_script}
```

## Adding New Scripts

When adding new scripts to this directory:

1. Create the script with clear documentation
2. Use `${VARIABLE_NAME}` for placeholders that need substitution (e.g., `${domain_name}`)
3. Update `terraform/main.tf` to load the script with `templatefile()`
4. Update `cloud-init/bootstrap.yml` to inject the script via template variable
5. Add entry to this README
6. Test the script with shellcheck: `shellcheck scripts/azure-vm/yourscript.sh`

## Deployment Method

Scripts in this directory are deployed via **Terraform templatefile()** injection:
- Keeps scripts private (never uploaded to public repository)
- Terraform reads the script file locally
- Substitutes template variables (e.g., `${domain_name}`)
- Injects rendered content into cloud-init during `terraform apply`

To update scripts on existing VMs, use `terraform taint` + `terraform apply` to redeploy.
