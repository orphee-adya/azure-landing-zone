###############################################################################
# Azure Firewall — point unique d'inspection Nord-Sud et Est-Ouest
# Par défaut tout est refusé : seules les règles ci-dessous sont autorisées.
# Les équipes applicatives ajoutent leurs règles via des rule collection
# groups dédiés (priorité >= 1000), revus par l'équipe réseau (CODEOWNERS).
###############################################################################

resource "azurerm_public_ip" "firewall" {
  name                = "pip-${local.c.names.firewall}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = local.tags
}

resource "azurerm_firewall_policy" "hub" {
  name                     = local.c.names.firewall_policy
  resource_group_name      = azurerm_resource_group.hub.name
  location                 = var.location
  sku                      = var.firewall_sku_tier
  threat_intelligence_mode = "Deny"

  dns {
    proxy_enabled = true # requis pour les règles réseau FQDN et le DNS centralisé
  }

  dynamic "intrusion_detection" {
    for_each = var.firewall_sku_tier == "Premium" ? [1] : []
    content {
      mode = "Deny"
    }
  }

  tags = local.tags
}

resource "azurerm_firewall" "hub" {
  name                = local.c.names.firewall
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku_tier
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  zones               = var.zones

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  tags = local.tags
}

resource "azurerm_firewall_policy_rule_collection_group" "platform" {
  name               = "rcg-platform"
  firewall_policy_id = azurerm_firewall_policy.hub.id
  priority           = 200

  network_rule_collection {
    name     = "allow-platform-network"
    priority = 200
    action   = "Allow"

    rule {
      name                  = "active-directory-tcp"
      protocols             = ["TCP"]
      source_addresses      = var.internal_address_ranges
      destination_addresses = [var.identity_address_space]
      destination_ports     = ["53", "88", "135", "389", "445", "464", "636", "3268-3269", "9389", "49152-65535"]
    }

    rule {
      name                  = "active-directory-udp"
      protocols             = ["UDP"]
      source_addresses      = var.internal_address_ranges
      destination_addresses = [var.identity_address_space]
      destination_ports     = ["53", "88", "123", "389", "464"]
    }

    rule {
      name              = "azure-kms"
      protocols         = ["TCP"]
      source_addresses  = var.internal_address_ranges
      destination_fqdns = ["azkms.core.windows.net", "kms.core.windows.net"]
      destination_ports = ["1688"]
    }
  }

  application_rule_collection {
    name     = "allow-platform-app"
    priority = 300
    action   = "Allow"

    rule {
      name                  = "windows-update"
      source_addresses      = var.internal_address_ranges
      destination_fqdn_tags = ["WindowsUpdate"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "azure-monitor-agent"
      source_addresses = var.internal_address_ranges
      destination_fqdns = [
        "global.handler.control.monitor.azure.com",
        "${var.location}.handler.control.monitor.azure.com",
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
        "*.monitoring.azure.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

# Journaux du pare-feu -> Log Analytics plateforme (tables dédiées AZFW*)
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  name                           = "diag-to-law-platform"
  target_resource_id             = azurerm_firewall.hub.id
  log_analytics_workspace_id     = local.c.ids.law_platform
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}
