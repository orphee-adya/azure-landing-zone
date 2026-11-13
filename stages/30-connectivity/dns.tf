###############################################################################
# DNS centralisé
#  - Zones privatelink hébergées dans la souscription connectivity ; les
#    enregistrements sont créés automatiquement par la policy ALZ
#    "Deploy-Private-DNS-Zones" (MG Corp) lors de la création des private endpoints.
#  - DNS Private Resolver : inbound (on-prem -> Azure), outbound + ruleset
#    (Azure -> DNS on-prem) si des redirections sont définies.
###############################################################################

resource "azurerm_resource_group" "dns" {
  name     = local.c.resource_groups.dns
  location = var.location
  tags     = local.tags
}

locals {
  private_dns_zones = toset(concat([
    "privatelink.blob.core.windows.net",
    "privatelink.dfs.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.queue.core.windows.net",
    "privatelink.table.core.windows.net",
    "privatelink.web.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.managedhsm.azure.net",
    "privatelink.database.windows.net",
    "privatelink.postgres.database.azure.com",
    "privatelink.mysql.database.azure.com",
    "privatelink.documents.azure.com",
    "privatelink.redis.cache.windows.net",
    "privatelink.servicebus.windows.net",
    "privatelink.azurewebsites.net",
    "privatelink.azurecr.io",
    "privatelink.${var.location}.azmk8s.io",
    "privatelink.cognitiveservices.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.monitor.azure.com",
    "privatelink.oms.opinsights.azure.com",
    "privatelink.ods.opinsights.azure.com",
    "privatelink.agentsvc.azure-automation.net",
    "privatelink.azure-automation.net",
    "privatelink.siterecovery.windowsazure.com",
    "privatelink.datafactory.azure.net",
    "privatelink.adf.azure.com",
    "privatelink.search.windows.net",
    "privatelink.eventgrid.azure.net",
  ], var.additional_private_dns_zones))
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.private_dns_zones
  name                = each.value
  resource_group_name = azurerm_resource_group.dns.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "hub" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${azurerm_virtual_network.hub.name}"
  resource_group_name   = azurerm_resource_group.dns.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.hub.id
  registration_enabled  = false
  tags                  = local.tags
}

#------------------------------------------------------------------------------
# DNS Private Resolver
#------------------------------------------------------------------------------
resource "azurerm_subnet" "dns_inbound" {
  count                = var.dns_resolver_enabled ? 1 : 0
  name                 = "snet-dns-inbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnets.dns_inbound]

  delegation {
    name = "dnsresolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet" "dns_outbound" {
  count                = var.dns_resolver_enabled ? 1 : 0
  name                 = "snet-dns-outbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnets.dns_outbound]

  delegation {
    name = "dnsresolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_resolver" "hub" {
  count               = var.dns_resolver_enabled ? 1 : 0
  name                = local.c.names.dns_resolver
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  virtual_network_id  = azurerm_virtual_network.hub.id
  tags                = local.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "hub" {
  count                   = var.dns_resolver_enabled ? 1 : 0
  name                    = "in-${local.c.names.dns_resolver}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = var.location

  ip_configurations {
    private_ip_allocation_method = "Dynamic"
    subnet_id                    = azurerm_subnet.dns_inbound[0].id
  }

  tags = local.tags
}

resource "azurerm_private_dns_resolver_outbound_endpoint" "hub" {
  count                   = var.dns_resolver_enabled && length(var.dns_forwarding_rules) > 0 ? 1 : 0
  name                    = "out-${local.c.names.dns_resolver}"
  private_dns_resolver_id = azurerm_private_dns_resolver.hub[0].id
  location                = var.location
  subnet_id               = azurerm_subnet.dns_outbound[0].id
  tags                    = local.tags
}

resource "azurerm_private_dns_resolver_dns_forwarding_ruleset" "onprem" {
  count                                      = var.dns_resolver_enabled && length(var.dns_forwarding_rules) > 0 ? 1 : 0
  name                                       = "dnsfrs-${var.org}-onprem-${var.location_short}"
  resource_group_name                        = azurerm_resource_group.hub.name
  location                                   = var.location
  private_dns_resolver_outbound_endpoint_ids = [azurerm_private_dns_resolver_outbound_endpoint.hub[0].id]
  tags                                       = local.tags
}

resource "azurerm_private_dns_resolver_forwarding_rule" "onprem" {
  for_each                  = var.dns_resolver_enabled ? var.dns_forwarding_rules : {}
  name                      = replace(trimsuffix(each.key, "."), ".", "-")
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.onprem[0].id
  domain_name               = each.key
  enabled                   = true

  dynamic "target_dns_servers" {
    for_each = each.value
    content {
      ip_address = target_dns_servers.value
      port       = 53
    }
  }
}

resource "azurerm_private_dns_resolver_virtual_network_link" "hub" {
  count                     = var.dns_resolver_enabled && length(var.dns_forwarding_rules) > 0 ? 1 : 0
  name                      = "link-${azurerm_virtual_network.hub.name}"
  dns_forwarding_ruleset_id = azurerm_private_dns_resolver_dns_forwarding_ruleset.onprem[0].id
  virtual_network_id        = azurerm_virtual_network.hub.id
}
