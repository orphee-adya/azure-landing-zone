###############################################################################
# BOOTSTRAP — exécuté UNE fois, en local, par un administrateur ayant
# "Elevate access" (User Access Administrator sur "/") :
#   1. Management group racine intermédiaire (<org>) sous le Tenant Root Group
#   2. Backend d'état Terraform (stockage durci, auth Entra ID uniquement)
#   3. Deux identités managées (plan / apply) fédérées avec GitHub (OIDC, sans secret)
#   4. RBAC minimal pour la CI
#   5. Environnements + variables GitHub (github.tf)
###############################################################################

data "azurerm_client_config" "current" {}

module "conventions" {
  source           = "../modules/conventions"
  org              = var.org
  location_short   = var.location_short
  subscription_ids = var.subscription_ids
  tags             = var.tags
}

locals {
  tenant_root_mg_id    = "/providers/Microsoft.Management/managementGroups/${data.azurerm_client_config.current.tenant_id}"
  storage_account_name = coalesce(var.state_storage_account_name, "st${var.org}tfstate${var.location_short}")
  tags                 = module.conventions.tags

  github_environments = {
    plan  = "alz-plan"
    apply = "alz-apply"
  }
}

#------------------------------------------------------------------------------
# 1. Management group racine intermédiaire
#    Créé ici (et non dans 00-governance) pour pouvoir y donner Owner à la CI
#    sans lui accorder de droits sur le Tenant Root Group.
#------------------------------------------------------------------------------
resource "azurerm_management_group" "root" {
  name                       = module.conventions.management_groups.root
  display_name               = var.org_display_name
  parent_management_group_id = local.tenant_root_mg_id

  # Le placement des souscriptions est géré par 00-governance
  lifecycle {
    ignore_changes = [subscription_ids]
  }
}

#------------------------------------------------------------------------------
# 2. Backend d'état
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "tfstate" {
  name     = module.conventions.resource_groups.tfstate
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                              = local.storage_account_name
  resource_group_name               = azurerm_resource_group.tfstate.name
  location                          = var.location
  account_kind                      = "StorageV2"
  account_tier                      = "Standard"
  account_replication_type          = var.state_replication_type
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false # Entra ID uniquement
  default_to_oauth_authentication   = true
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  public_network_access_enabled     = var.state_public_network_access_enabled
  cross_tenant_replication_enabled  = false

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

resource "azurerm_management_lock" "tfstate" {
  name       = "lock-tfstate"
  scope      = azurerm_resource_group.tfstate.id
  lock_level = "CanNotDelete"
  notes      = "Etat Terraform de la landing zone - ne pas supprimer."
}

locals {
  tfstate_container_scope = "${azurerm_storage_account.tfstate.id}/blobServices/default/containers/${azurerm_storage_container.tfstate.name}"
}

#------------------------------------------------------------------------------
# 3. Identités CI/CD (OIDC GitHub, aucun secret stocké)
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "cicd" {
  name     = module.conventions.resource_groups.cicd
  location = var.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "cicd" {
  for_each            = local.github_environments
  name                = "id-${var.org}-alz-${each.key}-${var.location_short}"
  resource_group_name = azurerm_resource_group.cicd.name
  location            = var.location
  tags                = local.tags
}

# Le "subject" lie le jeton OIDC à UN environnement GitHub précis :
# seul un job déclarant `environment: alz-apply` peut obtenir l'identité apply.
resource "azurerm_federated_identity_credential" "github" {
  for_each            = local.github_environments
  name                = "github-${var.github_repository}-${each.value}"
  resource_group_name = azurerm_resource_group.cicd.name
  parent_id           = azurerm_user_assigned_identity.cicd[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_owner}/${var.github_repository}:environment:${each.value}"
}

#------------------------------------------------------------------------------
# 4. RBAC de la CI
#------------------------------------------------------------------------------
locals {
  role_assignments = merge(
    {
      # --- Identité APPLY ---
      apply_owner_root = {
        identity = "apply"
        scope    = azurerm_management_group.root.id
        role     = "Owner" # policies DINE + role assignments => Owner requis (cf. README §Durcissement)
      }
      apply_mgcontrib_tenantroot = {
        identity = "apply"
        scope    = local.tenant_root_mg_id
        role     = "Management Group Contributor" # déplacement des souscriptions depuis le Tenant Root
      }
      apply_state = {
        identity = "apply"
        scope    = local.tfstate_container_scope
        role     = "Storage Blob Data Contributor"
      }
      # --- Identité PLAN (lecture seule + verrou d'état) ---
      plan_reader_root = {
        identity = "plan"
        scope    = azurerm_management_group.root.id
        role     = "Reader"
      }
      plan_state = {
        identity = "plan"
        scope    = local.tfstate_container_scope
        role     = "Storage Blob Data Contributor" # nécessaire pour poser le lease (lock)
      }
    },
    # Droits explicites sur les souscriptions plateforme tant qu'elles sont
    # encore sous le Tenant Root (avant placement par 00-governance)
    { for k, id in var.subscription_ids : "apply_owner_${k}" => {
      identity = "apply"
      scope    = "/subscriptions/${id}"
      role     = "Owner"
    } },
    { for k, id in var.subscription_ids : "plan_reader_${k}" => {
      identity = "plan"
      scope    = "/subscriptions/${id}"
      role     = "Reader"
    } }
  )
}

resource "azurerm_role_assignment" "cicd" {
  for_each             = local.role_assignments
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.cicd[each.value.identity].principal_id
  principal_type       = "ServicePrincipal"
  description          = "ALZ CI/CD (${each.value.identity})"
}

# L'administrateur qui lance le bootstrap doit pouvoir lire/écrire l'état
# (clés de stockage désactivées => accès Entra ID uniquement), notamment pour
# `terraform init -migrate-state`.
resource "azurerm_role_assignment" "admin_state" {
  scope                = local.tfstate_container_scope
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  description          = "Administrateur bootstrap - accès à l'état Terraform"
}
