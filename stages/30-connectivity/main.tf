###############################################################################
# STAGE 30 — Connectivity (souscription "connectivity")
# Topologie hub & spoke :
#   - VNet hub, Azure Firewall (Premium) + policy, Bastion
#   - Passerelle VPN (option), plan DDoS (option)
#   - Zones DNS privées privatelink + DNS Private Resolver
# Les spokes sont créés par 40-identity et 50-subscription-vending.
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

resource "azurerm_resource_group" "hub" {
  name     = local.c.resource_groups.hub
  location = var.location
  tags     = local.tags
}

#------------------------------------------------------------------------------
# DDoS (option)
#------------------------------------------------------------------------------
resource "azurerm_resource_group" "ddos" {
  count    = var.ddos_protection_enabled ? 1 : 0
  name     = local.c.resource_groups.ddos
  location = var.location
  tags     = local.tags
}

resource "azurerm_network_ddos_protection_plan" "this" {
  count               = var.ddos_protection_enabled ? 1 : 0
  name                = local.c.names.ddos_plan
  resource_group_name = azurerm_resource_group.ddos[0].name
  location            = var.location
  tags                = local.tags
}

#------------------------------------------------------------------------------
# VNet hub
#------------------------------------------------------------------------------
resource "azurerm_virtual_network" "hub" {
  name                = local.c.names.hub_vnet
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  address_space       = [var.hub_address_space]

  dynamic "ddos_protection_plan" {
    for_each = var.ddos_protection_enabled ? [1] : []
    content {
      id     = azurerm_network_ddos_protection_plan.this[0].id
      enable = true
    }
  }

  tags = local.tags
}

# DNS du hub = proxy DNS du pare-feu (défini après création du FW pour éviter un cycle)
resource "azurerm_virtual_network_dns_servers" "hub" {
  virtual_network_id = azurerm_virtual_network.hub.id
  dns_servers        = [azurerm_firewall.hub.ip_configuration[0].private_ip_address]
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnets.firewall]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnets.gateway]
}

resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [var.hub_subnets.bastion]
}

#------------------------------------------------------------------------------
# Bastion
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "bastion" {
  count               = var.bastion_enabled ? 1 : 0
  name                = "pip-${local.c.names.bastion}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = local.tags
}

resource "azurerm_bastion_host" "hub" {
  count               = var.bastion_enabled ? 1 : 0
  name                = local.c.names.bastion
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  sku                 = "Standard"
  tunneling_enabled   = true # az network bastion ssh/rdp natif
  copy_paste_enabled  = true

  ip_configuration {
    name                 = "ipconfig"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion[0].id
  }

  tags = local.tags
}

#------------------------------------------------------------------------------
# Passerelle VPN (option)
#------------------------------------------------------------------------------
resource "azurerm_public_ip" "vpn" {
  count               = var.vpn_gateway_enabled ? 1 : 0
  name                = "pip-${local.c.names.vpn_gateway}"
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = local.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.vpn_gateway_enabled ? 1 : 0
  name                = local.c.names.vpn_gateway
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_gateway_sku
  generation          = "Generation2"
  active_active       = false
  bgp_enabled         = false

  ip_configuration {
    name                          = "vnetGatewayConfig"
    public_ip_address_id          = azurerm_public_ip.vpn[0].id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  tags = local.tags
}

# Trafic on-prem -> spokes forcé à travers le pare-feu
resource "azurerm_route_table" "gateway" {
  count                         = var.vpn_gateway_enabled ? 1 : 0
  name                          = "rt-${var.org}-gateway-${var.location_short}"
  resource_group_name           = azurerm_resource_group.hub.name
  location                      = var.location
  bgp_route_propagation_enabled = true

  dynamic "route" {
    for_each = toset(var.spoke_supernets)
    content {
      name                   = "to-spoke-${replace(replace(route.value, ".", "-"), "/", "_")}"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = azurerm_firewall.hub.ip_configuration[0].private_ip_address
    }
  }

  tags = local.tags
}

resource "azurerm_subnet_route_table_association" "gateway" {
  count          = var.vpn_gateway_enabled ? 1 : 0
  subnet_id      = azurerm_subnet.gateway.id
  route_table_id = azurerm_route_table.gateway[0].id
}
