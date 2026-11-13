output "sentinel_workspace_id" {
  value = azurerm_log_analytics_workspace.sentinel.id
}

output "key_vault_id" {
  value = azurerm_key_vault.platform.id
}

output "key_vault_uri" {
  value = azurerm_key_vault.platform.vault_uri
}
