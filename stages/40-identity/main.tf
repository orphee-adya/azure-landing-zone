###############################################################################
# STAGE 40 — Identity (souscription "identity")
# Spoke réseau pour AD DS / Entra Domain Services / serveurs Entra Connect.
# Les VM contrôleurs de domaine ne sont pas déployées ici (cycle de vie
# différent : à gérer par l'équipe identité dans ce même spoke).
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

data "terraform_remote_state" "connectivity" {
  backend = "azurerm"
  config = {
    subscription_id      = var.tfstate.subscription_id
    resource_group_name  = var.tfstate.resource_group_name
    storage_account_name = var.tfstate.storage_account_name
    container_name       = var.tfstate.container_name
    key                  = "30-connectivity.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  hub = data.terraform_remote_state.connectivity.outputs
}

resource "azurerm_resource_group" "identity" {
  name     = local.c.resource_groups.identity
  location = var.location
  tags     = local.tags
}

module "identity_spoke" {
  source = "../../modules/spoke-network"
  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.connectivity
  }

  name                = local.c.names.identity_vnet
  resource_group_name = azurerm_resource_group.identity.name
  location            = var.location
  address_space       = [var.identity_address_space]
  dns_servers         = [local.hub.firewall_private_ip]
  firewall_private_ip = local.hub.firewall_private_ip

  hub_vnet_id             = local.hub.hub_vnet_id
  hub_vnet_name           = local.hub.hub_vnet_name
  hub_resource_group_name = local.hub.hub_resource_group_name
  use_remote_gateways     = local.hub.vpn_gateway_enabled

  subnets = {
    domain-controllers = {
      address_prefix = var.domain_controller_subnet
      security_rules = {
        allow-ad-tcp = {
          priority                   = 100
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefixes    = var.internal_address_ranges
          destination_address_prefix = var.domain_controller_subnet
          destination_port_ranges    = ["53", "88", "135", "389", "445", "464", "636", "3268-3269", "9389", "49152-65535"]
        }
        allow-ad-udp = {
          priority                   = 110
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Udp"
          source_address_prefixes    = var.internal_address_ranges
          destination_address_prefix = var.domain_controller_subnet
          destination_port_ranges    = ["53", "88", "123", "389", "464"]
        }
        allow-bastion = {
          priority                   = 200
          direction                  = "Inbound"
          access                     = "Allow"
          protocol                   = "Tcp"
          source_address_prefixes    = [var.bastion_subnet]
          destination_address_prefix = var.domain_controller_subnet
          destination_port_ranges    = ["22", "3389"]
        }
        deny-all-inbound = {
          priority                   = 4096
          direction                  = "Inbound"
          access                     = "Deny"
          protocol                   = "*"
          source_address_prefixes    = ["0.0.0.0/0"]
          destination_address_prefix = "*"
          destination_port_ranges    = ["0-65535"]
        }
      }
    }
  }

  tags = local.tags
}
