output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.platform.id
}

output "log_analytics_workspace_workspace_id" {
  description = "GUID du workspace (customer ID)."
  value       = azurerm_log_analytics_workspace.platform.workspace_id
}

output "action_group_id" {
  value = azurerm_monitor_action_group.platform.id
}

output "ama_identity_id" {
  value = azurerm_user_assigned_identity.ama.id
}

output "data_collection_rule_ids" {
  value = {
    vminsights     = azurerm_monitor_data_collection_rule.vminsights.id
    changetracking = azurerm_monitor_data_collection_rule.changetracking.id
    defendersql    = azurerm_monitor_data_collection_rule.defendersql.id
  }
}

output "log_archive_storage_account_id" {
  value = azurerm_storage_account.log_archive.id
}
