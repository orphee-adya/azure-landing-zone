###############################################################################
# Environnements et variables GitHub
#  - alz-plan  : pas d'approbation, identité lecture seule (PR + drift)
#  - alz-apply : approbation obligatoire, branches protégées uniquement
###############################################################################

data "github_team" "approvers" {
  for_each = var.manage_github ? toset(var.github_apply_reviewer_teams) : toset([])
  slug     = each.value
}

resource "github_repository_environment" "plan" {
  count       = var.manage_github ? 1 : 0
  repository  = var.github_repository
  environment = local.github_environments.plan
}

resource "github_repository_environment" "apply" {
  count               = var.manage_github ? 1 : 0
  repository          = var.github_repository
  environment         = local.github_environments.apply
  prevent_self_review = var.github_prevent_self_review
  wait_timer          = 0

  reviewers {
    teams = [for t in data.github_team.approvers : tonumber(t.id)]
  }

  deployment_branch_policy {
    protected_branches     = true
    custom_branch_policies = false
  }
}

resource "github_actions_environment_variable" "client_id" {
  for_each = var.manage_github ? {
    plan  = github_repository_environment.plan[0].environment
    apply = github_repository_environment.apply[0].environment
  } : {}
  repository    = var.github_repository
  environment   = each.value
  variable_name = "AZURE_CLIENT_ID"
  value         = azurerm_user_assigned_identity.cicd[each.key].client_id
}

resource "github_actions_variable" "repo" {
  for_each = var.manage_github ? {
    AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
    TFSTATE_SUBSCRIPTION_ID = var.subscription_ids.management
    TFSTATE_RESOURCE_GROUP  = azurerm_resource_group.tfstate.name
    TFSTATE_STORAGE_ACCOUNT = azurerm_storage_account.tfstate.name
    TFSTATE_CONTAINER       = azurerm_storage_container.tfstate.name
  } : {}
  repository    = var.github_repository
  variable_name = each.key
  value         = each.value
}
