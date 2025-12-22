# Azure WireGuard Secure Tunnel - Outputs

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

output "wireguard_config_template" {
  description = "Template for home WireGuard configuration"
  value = <<-EOT
    # Save this to home-configs/wireguard/wg0.conf
    # Then generate keys with: wg genkey | tee privatekey | wg pubkey > publickey
    
    [Interface]
    PrivateKey = <YOUR_HOME_PRIVATE_KEY>
    Address = ${var.wireguard_client_ip}/24
    
    [Peer]
    PublicKey = <AZURE_PUBLIC_KEY_FROM_VM>
    Endpoint = ${azurerm_public_ip.main.ip_address}:${var.wireguard_port}
    AllowedIPs = ${var.wireguard_server_ip}/32
    PersistentKeepalive = 25
  EOT
}

output "next_steps" {
  description = "Next steps after Terraform deployment"
  value = <<-EOT
    ✅ Azure infrastructure deployed successfully!
    
    Next steps:
    
    1. Wait ~5 minutes for cloud-init to complete
    
    2. SSH into the VM to get WireGuard public key:
       ${var.admin_username}@${azurerm_public_ip.main.ip_address}
       sudo cat /etc/wireguard/publickey
    
    3. Configure home WireGuard with the Azure public key
       (See wireguard_config_template output above)
    
    4. Start home Docker stack:
       cd home-configs && docker-compose up -d
    
    5. Sync your SSL certificates:
       ./scripts/sync-certs.sh
    
    6. Update DNS to point to Azure IP:
       ${var.domain_name} A ${azurerm_public_ip.main.ip_address}
       (or wait for auto-update on next VM boot)
    
    7. Test your setup:
       curl -I https://${var.domain_name}
    
    Estimated cost: ${var.vm_size == "Standard_B1ls" ? "$8.10/month" : "$14.30/month"}
  EOT
}

output "security_summary" {
  description = "Security configuration summary"
  value = {
    ssh_allowed_ipv4  = var.allowed_ssh_ipv4
    ssh_allowed_ipv6  = var.allowed_ssh_ipv6 != "" ? var.allowed_ssh_ipv6 : "Not configured"
    https_port        = 443
    wireguard_port    = var.wireguard_port
    password_auth     = "DISABLED"
    root_login        = "DISABLED"
    authentication    = "SSH Key Only"
  }
}
