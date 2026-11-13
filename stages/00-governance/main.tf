###############################################################################
# STAGE 00 — Gouvernance
#  - Hiérarchie de management groups (architecture ALZ)
#  - Bibliothèque de policies ALZ (sécurité, logging, réseau, Defender...)
#  - Placement des souscriptions plateforme
#  - Policies complémentaires (localisation) + RBAC des équipes
###############################################################################

data "azurerm_client_config" "current" {}

module "conventions" {
  source           = "../../modules/conventions"
  org              = var.org
  location_short   = var.location_short
  subscription_ids = var.subscription_ids
  tags             = var.tags
}

locals {
  c  = module.conventions
  mg = module.conventions.management_groups

  # Valeurs injectées dans les paramètres des assignations ALZ.
  # IDs calculés : les ressources sont créées par les stages suivants,
  # les policies DINE/Modify remédieront dès qu'elles existeront.
  policy_default_values = {
    log_analytics_workspace_id                  = jsonencode({ value = local.c.ids.law_platform })
    ama_user_assigned_managed_identity_id       = jsonencode({ value = local.c.ids.uami_ama })
    ama_user_assigned_managed_identity_name     = jsonencode({ value = local.c.names.uami_ama })
    ama_vm_insights_data_collection_rule_id     = jsonencode({ value = local.c.ids.dcr_vminsights })
    ama_change_tracking_data_collection_rule_id = jsonencode({ value = local.c.ids.dcr_changetracking })
    ama_mdfc_sql_data_collection_rule_id        = jsonencode({ value = local.c.ids.dcr_defendersql })
    ddos_protection_plan_id                     = jsonencode({ value = local.c.ids.ddos_plan })
    private_dns_zone_subscription_id            = jsonencode({ value = var.subscription_ids.connectivity })
    private_dns_zone_region                     = jsonencode({ value = var.location })
    private_dns_zone_resource_group_name        = jsonencode({ value = local.c.resource_groups.dns })
  }

  # Ajustements d'assignations ALZ existantes
  ddos_do_not_enforce = var.ddos_protection_enabled ? {} : {
    (local.mg.connectivity) = {
      policy_assignments = {
        "Enable-DDoS-VNET" = { enforcement_mode = "DoNotEnforce" }
      }
    }
    (local.mg.landing_zones) = {
      policy_assignments = {
        "Enable-DDoS-VNET" = { enforcement_mode = "DoNotEnforce" }
      }
    }
  }

  defender_contact = {
    (local.mg.root) = {
      policy_assignments = {
        "Deploy-MDFC-Config-H224" = {
          parameters = {
            emailSecurityContact = jsonencode({ value = var.platform_contact_email })
          }
        }
      }
    }
  }

  policy_assignments_to_modify = merge(local.defender_contact, local.ddos_do_not_enforce)
}

#------------------------------------------------------------------------------
# Hiérarchie + policies ALZ
#------------------------------------------------------------------------------
module "alz" {
  source  = "Azure/avm-ptn-alz/azurerm"
  version = "~> 0.12" # figer une version exacte après validation (ex : "0.12.0")

  architecture_name  = var.alz_architecture_name
  parent_resource_id = data.azurerm_client_config.current.tenant_id
  location           = var.location

  policy_default_values        = local.policy_default_values
  policy_assignments_to_modify = local.policy_assignments_to_modify

  subscription_placement = {
    management = {
      subscription_id       = var.subscription_ids.management
      management_group_name = local.mg.management
    }
    connectivity = {
      subscription_id       = var.subscription_ids.connectivity
      management_group_name = local.mg.connectivity
    }
    identity = {
      subscription_id       = var.subscription_ids.identity
      management_group_name = local.mg.identity
    }
    security = {
      subscription_id       = var.subscription_ids.security
      management_group_name = local.mg.security
    }
  }

  enable_telemetry = var.enable_telemetry
}

#------------------------------------------------------------------------------
# Policies complémentaires : souveraineté / localisation des données
#------------------------------------------------------------------------------
resource "azurerm_management_group_policy_assignment" "allowed_locations" {
  name                 = "Allowed-Locations"
  display_name         = "Régions autorisées pour les ressources"
  management_group_id  = local.c.management_group_ids.root
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  enforce              = true

  parameters = jsonencode({
    listOfAllowedLocations = { value = concat(var.allowed_locations, ["global"]) }
  })

  non_compliance_message {
    content = "Seules les régions ${join(", ", var.allowed_locations)} sont autorisées."
  }

  depends_on = [module.alz]
}

resource "azurerm_management_group_policy_assignment" "allowed_rg_locations" {
  name                 = "Allowed-RG-Locations"
  display_name         = "Régions autorisées pour les resource groups"
  management_group_id  = local.c.management_group_ids.root
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e765b5de-1225-4ba3-bd56-1ac6695af988"
  enforce              = true

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })

  depends_on = [module.alz]
}

#------------------------------------------------------------------------------
# RBAC des équipes (groupes Entra ID — jamais d'utilisateurs nominatifs)
#------------------------------------------------------------------------------
resource "azurerm_role_assignment" "teams" {
  for_each             = var.rbac_assignments
  scope                = local.c.management_group_ids[each.value.management_group]
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = "Group"
  description          = "ALZ RBAC - ${each.key}"

  depends_on = [module.alz]
}
