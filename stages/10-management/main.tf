###############################################################################
# STAGE 10 — Management (souscription "management")
#  - Log Analytics plateforme (cible des policies ALZ : Activity Logs,
#    diagnostics, VM Insights, Change Tracking, Defender SQL)
#  - Identité managée pour Azure Monitor Agent (AMA)
#  - Data Collection Rules (VM Insights, Change Tracking, Defender for SQL)
#  - Archivage long terme (stockage immuable + export continu)
#  - Action group + alerte Service Health
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

resource "azurerm_resource_group" "management" {
  name     = local.c.resource_groups.management
  location = var.location
  tags     = local.tags
}

#------------------------------------------------------------------------------
# Log Analytics plateforme
#------------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "platform" {
  name                       = local.c.names.law_platform
  resource_group_name        = azurerm_resource_group.management.name
  location                   = var.location
  sku                        = "PerGB2018"
  retention_in_days          = var.law_retention_days
  daily_quota_gb             = var.law_daily_quota_gb
  internet_ingestion_enabled = true # passer à false avec AMPLS + private endpoints
  internet_query_enabled     = true
  tags                       = local.tags
}

resource "azurerm_management_lock" "law" {
  name       = "lock-law-platform"
  scope      = azurerm_log_analytics_workspace.platform.id
  lock_level = "CanNotDelete"
  notes      = "Journalisation centrale de la plateforme."
}

#------------------------------------------------------------------------------
# Azure Monitor Agent : identité + DCR
#------------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "ama" {
  name                = local.c.names.uami_ama
  resource_group_name = azurerm_resource_group.management.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "vminsights" {
  name                = local.c.names.dcr_vminsights
  resource_group_name = azurerm_resource_group.management.name
  location            = var.location
  description         = "VM Insights (AMA) - performances"

  destinations {
    log_analytics {
      name                  = "law-platform"
      workspace_resource_id = azurerm_log_analytics_workspace.platform.id
    }
  }

  data_flow {
    streams      = ["Microsoft-InsightsMetrics"]
    destinations = ["law-platform"]
  }

  data_sources {
    performance_counter {
      name                          = "VMInsightsPerfCounters"
      streams                       = ["Microsoft-InsightsMetrics"]
      sampling_frequency_in_seconds = 60
      counter_specifiers            = ["\\VmInsights\\DetailedMetrics"]
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule" "changetracking" {
  name                = local.c.names.dcr_changetracking
  resource_group_name = azurerm_resource_group.management.name
  location            = var.location
  description         = "Change Tracking & Inventory (AMA)"

  destinations {
    log_analytics {
      name                  = "law-platform"
      workspace_resource_id = azurerm_log_analytics_workspace.platform.id
    }
  }

  data_flow {
    streams      = ["Microsoft-ConfigurationChange", "Microsoft-ConfigurationChangeV2", "Microsoft-ConfigurationData"]
    destinations = ["law-platform"]
  }

  data_sources {
    extension {
      name           = "CTDataSource-Windows"
      extension_name = "ChangeTracking-Windows"
      streams        = ["Microsoft-ConfigurationChange", "Microsoft-ConfigurationChangeV2", "Microsoft-ConfigurationData"]
      extension_json = jsonencode({
        enableFiles     = true
        enableSoftware  = true
        enableRegistry  = false
        enableServices  = true
        enableInventory = true
        fileSettings      = { fileCollectionFrequency = 2700 }
        softwareSettings  = { softwareCollectionFrequency = 1800 }
        inventorySettings = { inventoryCollectionFrequency = 36000 }
        servicesSettings  = { serviceCollectionFrequency = 1800 }
      })
    }

    extension {
      name           = "CTDataSource-Linux"
      extension_name = "ChangeTracking-Linux"
      streams        = ["Microsoft-ConfigurationChange", "Microsoft-ConfigurationChangeV2", "Microsoft-ConfigurationData"]
      extension_json = jsonencode({
        enableFiles     = true
        enableSoftware  = true
        enableRegistry  = false
        enableServices  = true
        enableInventory = true
        fileSettings      = { fileCollectionFrequency = 900 }
        softwareSettings  = { softwareCollectionFrequency = 300 }
        inventorySettings = { inventoryCollectionFrequency = 36000 }
        servicesSettings  = { serviceCollectionFrequency = 300 }
      })
    }
  }

  tags = local.tags
}

resource "azurerm_monitor_data_collection_rule" "defendersql" {
  name                = local.c.names.dcr_defendersql
  resource_group_name = azurerm_resource_group.management.name
  location            = var.location
  description         = "Microsoft Defender for SQL (AMA)"

  destinations {
    log_analytics {
      name                  = "law-platform"
      workspace_resource_id = azurerm_log_analytics_workspace.platform.id
    }
  }

  data_flow {
    streams = [
      "Microsoft-DefenderForSqlAlerts",
      "Microsoft-DefenderForSqlLogins",
      "Microsoft-DefenderForSqlTelemetry",
      "Microsoft-DefenderForSqlScanEvents",
      "Microsoft-DefenderForSqlScanResults",
    ]
    destinations = ["law-platform"]
  }

  data_sources {
    extension {
      name           = "MicrosoftDefenderForSQL"
      extension_name = "MicrosoftDefenderForSQL"
      streams = [
        "Microsoft-DefenderForSqlAlerts",
        "Microsoft-DefenderForSqlLogins",
        "Microsoft-DefenderForSqlTelemetry",
        "Microsoft-DefenderForSqlScanEvents",
        "Microsoft-DefenderForSqlScanResults",
      ]
      extension_json = jsonencode({
        enableCollectionOfSqlQueriesForSecurityResearch = false
      })
    }
  }

  tags = local.tags
}

#------------------------------------------------------------------------------
# Archivage long terme (conformité) : stockage WORM + export continu
#------------------------------------------------------------------------------
resource "azurerm_storage_account" "log_archive" {
  name                            = local.c.names.st_logarchive
  resource_group_name             = azurerm_resource_group.management.name
  location                        = var.location
  account_kind                    = "StorageV2"
  account_tier                    = "Standard"
  account_replication_type        = "ZRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true # export LAW = service de confiance ; restreindre via network_rules

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices", "Logging", "Metrics"]
  }

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
  }

  # Immutabilité au niveau compte (WORM) : rétention non modifiable une fois verrouillée
  immutability_policy {
    allow_protected_append_writes = true
    state                         = "Unlocked" # passer à "Locked" après validation (irréversible)
    period_since_creation_in_days = 365
  }

  tags = local.tags
}

resource "azurerm_storage_management_policy" "log_archive" {
  storage_account_id = azurerm_storage_account.log_archive.id

  rule {
    name    = "tiering-and-retention"
    enabled = true
    filters {
      blob_types = ["blockBlob", "appendBlob"]
    }
    actions {
      base_blob {
        tier_to_cool_after_days_since_modification_greater_than    = 30
        tier_to_archive_after_days_since_modification_greater_than = 180
        delete_after_days_since_modification_greater_than          = var.archive_retention_days
      }
    }
  }
}

resource "azurerm_log_analytics_data_export_rule" "archive" {
  name                    = "export-to-archive"
  resource_group_name     = azurerm_resource_group.management.name
  workspace_resource_id   = azurerm_log_analytics_workspace.platform.id
  destination_resource_id = azurerm_storage_account.log_archive.id
  table_names             = var.archive_exported_tables
  enabled                 = true
}

#------------------------------------------------------------------------------
# Alerting plateforme
# (Pour un socle d'alertes complet : Azure Monitor Baseline Alerts / AMBA,
#  ajoutable comme dépendance "platform/amba" de la bibliothèque ALZ.)
#------------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "platform" {
  name                = local.c.names.action_group
  resource_group_name = azurerm_resource_group.management.name
  short_name          = "alz-plat"

  email_receiver {
    name                    = "platform-team"
    email_address           = var.platform_contact_email
    use_common_alert_schema = true
  }

  tags = local.tags
}

resource "azurerm_monitor_activity_log_alert" "service_health" {
  name                = "alert-servicehealth-management"
  resource_group_name = azurerm_resource_group.management.name
  location            = "global"
  scopes              = ["/subscriptions/${var.subscription_ids.management}"]
  description         = "Incidents, maintenances et avis de sécurité Azure."

  criteria {
    category = "ServiceHealth"
    service_health {
      events    = ["Incident", "Maintenance", "Security"]
      locations = var.service_health_regions
    }
  }

  action {
    action_group_id = azurerm_monitor_action_group.platform.id
  }

  tags = local.tags
}
