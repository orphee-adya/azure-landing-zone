output "hub_vnet_id" {
  value = azurerm_virtual_network.hub.id
}

output "hub_vnet_name" {
  value = azurerm_virtual_network.hub.name
}

output "hub_resource_group_name" {
  value = azurerm_resource_group.hub.name
}

output "firewall_private_ip" {
  description = "Next hop des routes 0.0.0.0/0 et serveur DNS des spokes."
  value       = azurerm_firewall.hub.ip_configuration[0].private_ip_address
}

output "firewall_policy_id" {
  value = azurerm_firewall_policy.hub.id
}

output "vpn_gateway_enabled" {
  description = "Utilisé par les spokes pour activer use_remote_gateways."
  value       = var.vpn_gateway_enabled
}

output "dns_resolver_inbound_ip" {
  value = var.dns_resolver_enabled ? azurerm_private_dns_resolver_inbound_endpoint.hub[0].ip_configurations[0].private_ip_address : null
}

output "private_dns_zone_ids" {
  value = { for k, z in azurerm_private_dns_zone.this : k => z.id }
}
