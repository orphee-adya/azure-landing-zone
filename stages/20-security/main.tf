###############################################################################
# STAGE 20 — Security (souscription "security", MG Security — ALZ 2025+)
#  - Workspace Log Analytics dédié SOC + Microsoft Sentinel
#  - Journaux Entra ID -> Sentinel (option)
#  - Règle de création d'incidents depuis Defender for Cloud
#  - Key Vault plateforme (secrets partagés : PSK VPN, certificats TLS FW...)
#
# Séparation des responsabilités : le SOC administre ce workspace sans accès
# au workspace d'exploitation (management), et inversement.
###############################################################################

module "conventions" {
  source           = "../../modules/conventions"
  org              = var.org
  location_short   = var.location_short
  subscription_ids = var.subscription_ids
  tags             = var.tags
}

locals {
  c    = module.conventions
  tags = module.conventions.tags
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "security" {
  name     = local.c.resource_groups.security
  location = var.location
  tags     = local.tags
}

#------------------------------------------------------------------------------
# Sentinel
#------------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "sentinel" {
  name                = local.c.names.law_sentinel
  resource_group_name = azurerm_resource_group.security.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = var.sentinel_retention_days
  tags                = local.tags
}

resource "azurerm_management_lock" "sentinel" {
  name       = "lock-law-sentinel"
  scope      = azurerm_log_analytics_workspace.sentinel.id
  lock_level = "CanNotDelete"
  notes      = "Workspace SOC / Sentinel."
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "this" {
  workspace_id = azurerm_log_analytics_workspace.sentinel.id
}

# Incidents automatiques à partir des alertes Defender for Cloud
resource "azurerm_sentinel_alert_rule_ms_security_incident" "defender_for_cloud" {
  name                       = "defender-for-cloud-incidents"
  display_name               = "Incidents - Microsoft Defender for Cloud"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.this.workspace_id
  product_filter             = "Azure Security Center"
  severity_filter            = ["High", "Medium"]
}

# Journaux Entra ID (tenant-level)
resource "azurerm_monitor_aad_diagnostic_setting" "entra" {
  count                      = var.entra_diagnostics_enabled ? 1 : 0
  name                       = "entra-to-sentinel"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sentinel.id

  dynamic "enabled_log" {
    for_each = toset(var.entra_log_categories)
    content {
      category = enabled_log.value
    }
  }
}

#------------------------------------------------------------------------------
# Key Vault plateforme
#------------------------------------------------------------------------------
resource "azurerm_key_vault" "platform" {
  name                          = local.c.names.kv_security
  resource_group_name           = azurerm_resource_group.security.name
  location                      = var.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "premium" # HSM pour les clés sensibles
  enable_rbac_authorization     = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = length(var.key_vault_allowed_ips) > 0

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.key_vault_allowed_ips
  }

  tags = local.tags
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-to-sentinel"
  target_resource_id         = azurerm_key_vault.platform.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.sentinel.id

  enabled_log {
    category_group = "allLogs" # inclut "audit"
  }
}
