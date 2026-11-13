output "subscription_id" {
  value = local.subscription_id
}

output "vnet_id" {
  value = local.network_enabled ? azapi_resource.vnet[0].id : null
}

output "cicd_client_id" {
  description = "A configurer comme AZURE_CLIENT_ID dans le dépôt de l'équipe applicative."
  value       = var.github_oidc == null ? null : azapi_resource.cicd_identity[0].output.properties.clientId
}
