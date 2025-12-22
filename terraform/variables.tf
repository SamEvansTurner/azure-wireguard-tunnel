# Azure WireGuard Secure Tunnel - Variables

# Azure Configuration
variable "location" {
  description = "Azure region for resources"
  type        = string
  default     = "australiaeast"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-secure-tunnel"
}

# VM Configuration
variable "vm_size" {
  description = "Size of the VM (Standard_B1ls = $3.80/mo, Standard_B1s = $10/mo)"
  type        = string
  default     = "Standard_B1ls"

  validation {
    condition     = can(regex("^Standard_B[0-9]", var.vm_size))
    error_message = "VM size must be a B-series (burstable) VM for cost optimization."
  }
}

variable "admin_username" {
  description = "Admin username for the VM (NOT 'admin', 'root', or 'azureuser')"
  type        = string

  validation {
    condition     = !contains(["admin", "root", "azureuser", "ubuntu", "administrator"], lower(var.admin_username))
    error_message = "Please use a unique username, not a common default."
  }
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# Network Configuration
variable "vnet_address_space" {
  description = "Address space for the virtual network"
  type        = string
  default     = "10.1.0.0/16"
}

variable "subnet_address" {
  description = "Address prefix for the subnet"
  type        = string
  default     = "10.1.1.0/24"
}

variable "allowed_ssh_ipv4" {
  description = "Your home IPv4 address with /32 (for SSH whitelist)"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/32$", var.allowed_ssh_ipv4))
    error_message = "SSH IPv4 must be in CIDR format with /32 (e.g., 203.0.113.1/32)."
  }
}

variable "allowed_ssh_ipv6" {
  description = "Your home IPv6 address with /128 (optional, for SSH whitelist from IPv6)"
  type        = string
  default     = ""

  validation {
    condition     = var.allowed_ssh_ipv6 == "" || can(regex("^([0-9a-fA-F]{0,4}:){7}[0-9a-fA-F]{0,4}/128$", var.allowed_ssh_ipv6))
    error_message = "SSH IPv6 must be in CIDR format with /128 (e.g., 2001:db8::1/128) or leave empty."
  }
}

variable "availability_zones" {
  description = <<-EOT
    Availability zones for Public IP (zone-redundant by default).
    - ["1", "2", "3"]: Zone-redundant (recommended, required for RoutingPreference)
    - ["1"]: Single zone
    - []: No zones (only for non-zonal regions or if removing RoutingPreference)
  EOT
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "use_static_ip" {
  description = "Use static IP address (costs $0.85/month more than dynamic)"
  type        = bool
  default     = false
}

# WireGuard Configuration
variable "wireguard_port" {
  description = "UDP port for WireGuard"
  type        = number
  default     = 51820

  validation {
    condition     = var.wireguard_port >= 1024 && var.wireguard_port <= 65535
    error_message = "WireGuard port must be between 1024 and 65535."
  }
}

variable "wireguard_subnet" {
  description = "Subnet for WireGuard tunnel network"
  type        = string
  default     = "10.0.0.0/24"
}

variable "wireguard_server_ip" {
  description = "IP address for WireGuard server (Azure side)"
  type        = string
  default     = "10.0.0.1"
}

variable "wireguard_client_ip" {
  description = "IP address for WireGuard client (home side)"
  type        = string
  default     = "10.0.0.2"
}

# Domain and DNS Configuration
variable "domain_name" {
  description = "Your full domain name (e.g., services.yourdomain.com or svc.example.com)"
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.)+[a-z]{2,}$", var.domain_name))
    error_message = "Please provide a valid domain name (e.g., svc.example.au or services.example.com)."
  }
}

variable "subdomain" {
  description = "Subdomain part only (e.g., 'services' for services.yourdomain.com)"
  type        = string
  default     = "services"
}

variable "desec_token" {
  description = "deSEC API token for DNS updates"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.desec_token) > 10
    error_message = "deSEC token appears to be invalid or not set."
  }
}

# Application Configuration
variable "home_caddy_port" {
  description = "Port where home Caddy listens for proxied requests"
  type        = number
  default     = 8080
}

# Tags
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "SecureTunnel"
    CostCenter  = "Personal"
  }
}

# Template Content (injected by deploy-azure.sh)
variable "azure_caddyfile_content" {
  description = "Processed Caddyfile template content (injected at deploy time)"
  type        = string
  default     = ""
}

variable "azure_wireguard_config" {
  description = "Processed WireGuard config template content (injected at deploy time)"
  type        = string
  default     = ""
}
