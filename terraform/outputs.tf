# Azure WireGuard Secure Tunnel - Terraform Outputs
#
# Infrastructure facts only - next steps shown by Ansible after full deployment.

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vm_public_ip" {
  description = "Public IP address of the Azure VM"
  value       = azurerm_public_ip.main.ip_address
}

output "vm_fqdn" {
  description = "Fully qualified domain name of the Azure VM"
  value       = azurerm_public_ip.main.fqdn
}

output "ssh_connection" {
  description = "SSH connection command"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.main.ip_address}"
}

output "vm_name" {
  description = "Name of the virtual machine"
  value       = azurerm_linux_virtual_machine.main.name
}

output "vm_size" {
  description = "Size of the VM"
  value       = azurerm_linux_virtual_machine.main.size
}

output "estimated_monthly_cost" {
  description = "Estimated monthly cost in USD"
  value = var.vm_size == "Standard_B1ls" ? (
    var.use_static_ip ? "$8.95 (B1ls + static IP)" : "$8.10 (B1ls + dynamic IP)"
    ) : (
    var.use_static_ip ? "$15.15 (B1s + static IP)" : "$14.30 (B1s + dynamic IP)"
  )
}

output "security_summary" {
  description = "Security configuration summary"
  value = {
    ssh_allowed_ipv4 = var.allowed_ssh_ipv4
    ssh_allowed_ipv6 = var.allowed_ssh_ipv6 != "" ? var.allowed_ssh_ipv6 : "Not configured"
    https_port       = 443
    wireguard_port   = var.wireguard_port
    password_auth    = "DISABLED"
    root_login       = "DISABLED"
    authentication   = "SSH Key Only"
  }
}

# Azure subscription ID - auto-detected, passed to Ansible for bandwidth monitor
output "subscription_id" {
  description = "Azure subscription ID (auto-detected)"
  value       = data.azurerm_subscription.current.subscription_id
}
