# Azure WireGuard Secure Tunnel - Main Configuration
#
# This creates the Azure infrastructure.
# Application configuration (WireGuard, Caddy, etc.) is handled by Ansible.

terraform {
  required_version = ">= 1.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}

# Get current subscription for role assignments
data "azurerm_subscription" "current" {}

# Resource Group
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    var.tags,
    {
      ManagedBy = "Terraform"
      Project   = "SecureTunnel"
    }
  )
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.resource_group_name}"
  address_space       = [var.vnet_address_space]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  tags = var.tags
}

# Subnet
resource "azurerm_subnet" "main" {
  name                 = "snet-tunnel"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnet_address]
}

# Network Security Group
resource "azurerm_network_security_group" "main" {
  name                = "nsg-${var.resource_group_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow HTTPS from anywhere
  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Allow SSH from home IPv4
  security_rule {
    name                       = "AllowSSHFromHomeIPv4"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_ipv4
    destination_address_prefix = "*"
  }

  # Allow SSH from home IPv6 (only if configured)
  dynamic "security_rule" {
    for_each = var.allowed_ssh_ipv6 != "" ? [1] : []
    content {
      name                       = "AllowSSHFromHomeIPv6"
      priority                   = 111
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.allowed_ssh_ipv6
      destination_address_prefix = "*"
    }
  }

  # Allow WireGuard from anywhere
  security_rule {
    name                       = "AllowWireGuard"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = tostring(var.wireguard_port)
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = var.tags
}

# Public IP with Internet routing for 50% bandwidth cost savings
resource "azurerm_public_ip" "main" {
  name                = "pip-${var.resource_group_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static" # Required for Internet routing
  sku                 = "Standard"
  sku_tier            = "Regional"
  ip_version          = "IPv4"
  domain_name_label   = var.resource_group_name
  zones               = var.availability_zones

  # Internet routing uses commodity internet instead of Microsoft's backbone
  # This reduces egress costs from ~$0.175/GB to ~$0.087/GB (50% savings)
  # Trade-off: Slightly higher latency, but negligible for video streaming
  ip_tags = {
    RoutingPreference = "Internet"
  }

  tags = merge(
    var.tags,
    {
      RoutingType   = "Internet"
      CostOptimized = "true"
    }
  )
}

# Network Interface
resource "azurerm_network_interface" "main" {
  name                = "nic-${var.resource_group_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.main.id
  }

  tags = var.tags
}

# Associate NSG with NIC
resource "azurerm_network_interface_security_group_association" "main" {
  network_interface_id      = azurerm_network_interface.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

# Linux Virtual Machine
resource "azurerm_linux_virtual_machine" "main" {
  name                = "vm-${var.resource_group_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username

  # SSH key authentication ONLY - no passwords
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_public_key_path)
  }

  network_interface_ids = [
    azurerm_network_interface.main.id,
  ]

  os_disk {
    name                 = "osdisk-${var.resource_group_name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "minimal"
    version   = "latest"
  }

  # Minimal cloud-init - just installs python3 for Ansible
  custom_data = filebase64("${path.module}/../cloud-init/bootstrap.yml")

  # Enable System-Assigned Managed Identity for Azure API access
  # Used by bandwidth monitor to query Cost Management API
  identity {
    type = "SystemAssigned"
  }

  # Boot diagnostics
  boot_diagnostics {
    storage_account_uri = null
  }

  tags = merge(
    var.tags,
    {
      Name = "Secure Tunnel VM"
      OS   = "Ubuntu Minimal 24.04 LTS"
    }
  )
}

# Grant VM managed identity access to Cost Management API
# Required for bandwidth monitor to query Azure spending
resource "azurerm_role_assignment" "vm_cost_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Cost Management Reader"
  principal_id         = azurerm_linux_virtual_machine.main.identity[0].principal_id
}
