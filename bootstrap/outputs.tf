output "intermediate_root_management_group_id" {
  value = azurerm_management_group.root.id
}

output "tfstate" {
  description = "A reporter dans config/common.tfvars (bloc tfstate)."
  value = {
    subscription_id      = var.subscription_ids.management
    resource_group_name  = azurerm_resource_group.tfstate.name
    storage_account_name = azurerm_storage_account.tfstate.name
    container_name       = azurerm_storage_container.tfstate.name
  }
}

output "cicd_identities" {
  description = "Client IDs des identités CI/CD (déjà poussés dans GitHub si manage_github = true)."
  value = {
    for k, v in azurerm_user_assigned_identity.cicd : k => {
      client_id    = v.client_id
      principal_id = v.principal_id
    }
  }
}
