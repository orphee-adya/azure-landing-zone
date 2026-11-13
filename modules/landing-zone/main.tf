###############################################################################
# Module landing-zone (subscription vending)
# Crée / adopte une souscription applicative et la livre "prête à l'emploi" :
#   - alias de souscription (EA/MCA) + placement dans le MG (Corp/Online/Sandbox)
#   - enregistrement des resource providers
#   - VNet spoke peeré au hub, UDR vers le pare-feu, NSG par sous-réseau
#   - RBAC de l'équipe applicative
#   - identité CI/CD fédérée GitHub (OIDC) pour l'équipe applicative
#   - budget + alertes
#
# Les ressources DANS la nouvelle souscription sont créées via azapi
# (parent_id explicite) : Terraform ne permet pas de déclarer un provider
# azurerm par souscription de façon dynamique.
###############################################################################

terraform {
  required_providers {
    azurerm = {
      source                = "hashicorp/azurerm"
      version               = "~> 4.50"
      configuration_aliases = [azurerm.hub]
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }
}

locals {
  create_subscription = var.subscription.existing_id == null
  subscription_id     = local.create_subscription ? azurerm_subscription.this[0].subscription_id : var.subscription.existing_id
  subscription_scope  = "/subscriptions/${local.subscription_id}"

  network_enabled = var.network != null
  hub_connected   = try(var.network.connect_to_hub, false) == true
}

#------------------------------------------------------------------------------
# Souscription
#------------------------------------------------------------------------------
resource "azurerm_subscription" "this" {
  count             = local.create_subscription ? 1 : 0
  alias             = "sub-${var.name}"
  subscription_name = var.subscription.display_name
  billing_scope_id  = var.billing_scope_id
  workload          = var.subscription.workload
  tags              = var.tags

  # Supprimer l'alias annule la souscription : décommissionner en déplaçant
  # la LZ vers le MG "decommissioned" plutôt qu'en supprimant le YAML.
  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_group_subscription_association" "this" {
  management_group_id = var.management_group_id
  subscription_id     = local.subscription_scope
}

resource "azapi_resource_action" "resource_providers" {
  for_each    = toset(var.resource_providers)
  type        = "Microsoft.Resources/resourceProviders@2021-04-01"
  resource_id = "${local.subscription_scope}/providers/${each.value}"
  action      = "register"
  method      = "POST"

  depends_on = [azurerm_management_group_subscription_association.this]
}

#------------------------------------------------------------------------------
# Réseau spoke
#------------------------------------------------------------------------------
resource "azapi_resource" "rg_network" {
  count     = local.network_enabled ? 1 : 0
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = "rg-${var.name}-network-${var.location_short}"
  parent_id = local.subscription_scope
  location  = var.location
  tags      = var.tags

  # Les policies du MG cible doivent s'appliquer dès la création
  depends_on = [azurerm_management_group_subscription_association.this, azapi_resource_action.resource_providers]
}

resource "azapi_resource" "route_table" {
  count     = local.hub_connected ? 1 : 0
  type      = "Microsoft.Network/routeTables@2024-05-01"
  name      = "rt-${var.name}-${var.location_short}"
  parent_id = azapi_resource.rg_network[0].id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      disableBgpRoutePropagation = true
      routes = [
        {
          name = "default-to-firewall"
          properties = {
            addressPrefix    = "0.0.0.0/0"
            nextHopType      = "VirtualAppliance"
            nextHopIpAddress = var.hub.firewall_private_ip
          }
        }
      ]
    }
  }
}

resource "azapi_resource" "nsg" {
  for_each  = try(var.network.subnets, {})
  type      = "Microsoft.Network/networkSecurityGroups@2024-05-01"
  name      = "nsg-${var.name}-${each.key}"
  parent_id = azapi_resource.rg_network[0].id
  location  = var.location
  tags      = var.tags

  body = {
    properties = {
      securityRules = []
    }
  }
}

resource "azapi_resource" "vnet" {
  count     = local.network_enabled ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks@2024-05-01"
  name      = "vnet-${var.name}-${var.location_short}"
  parent_id = azapi_resource.rg_network[0].id
  location  = var.location
  tags      = var.tags

  body = {
    properties = merge(
      {
        addressSpace = { addressPrefixes = var.network.address_space }
        subnets = [
          for k, s in var.network.subnets : {
            name = "snet-${k}"
            properties = merge(
              {
                addressPrefix                  = s.address_prefix
                defaultOutboundAccess          = false
                privateEndpointNetworkPolicies = "Enabled"
                networkSecurityGroup           = { id = azapi_resource.nsg[k].id }
              },
              local.hub_connected ? { routeTable = { id = azapi_resource.route_table[0].id } } : {}
            )
          }
        ]
      },
      local.hub_connected ? { dhcpOptions = { dnsServers = [var.hub.firewall_private_ip] } } : {}
    )
  }
}

# Côté hub en premier (allowGatewayTransit avant useRemoteGateways)
resource "azurerm_virtual_network_peering" "hub_to_spoke" {
  count                        = local.hub_connected ? 1 : 0
  provider                     = azurerm.hub
  name                         = "peer-to-${var.name}"
  resource_group_name          = var.hub.resource_group_name
  virtual_network_name         = var.hub.vnet_name
  remote_virtual_network_id    = azapi_resource.vnet[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.hub.use_remote_gateways
}

resource "azapi_resource" "spoke_to_hub" {
  count     = local.hub_connected ? 1 : 0
  type      = "Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01"
  name      = "peer-to-hub"
  parent_id = azapi_resource.vnet[0].id

  body = {
    properties = {
      remoteVirtualNetwork      = { id = var.hub.vnet_id }
      allowVirtualNetworkAccess = true
      allowForwardedTraffic     = true
      allowGatewayTransit       = false
      useRemoteGateways         = var.hub.use_remote_gateways
    }
  }

  depends_on = [azurerm_virtual_network_peering.hub_to_spoke]
}

#------------------------------------------------------------------------------
# RBAC équipe applicative
#------------------------------------------------------------------------------
resource "azurerm_role_assignment" "team" {
  for_each             = var.role_assignments
  scope                = local.subscription_scope
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
  principal_type       = try(each.value.principal_type, "Group")
  description          = "LZ ${var.name} - ${each.key}"

  depends_on = [azurerm_management_group_subscription_association.this]
}

#------------------------------------------------------------------------------
# Identité CI/CD de l'équipe applicative (GitHub OIDC)
#------------------------------------------------------------------------------
resource "azapi_resource" "rg_identity" {
  count     = var.github_oidc == null ? 0 : 1
  type      = "Microsoft.Resources/resourceGroups@2024-03-01"
  name      = "rg-${var.name}-identity-${var.location_short}"
  parent_id = local.subscription_scope
  location  = var.location
  tags      = var.tags

  depends_on = [azurerm_management_group_subscription_association.this, azapi_resource_action.resource_providers]
}

resource "azapi_resource" "cicd_identity" {
  count                  = var.github_oidc == null ? 0 : 1
  type                   = "Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31"
  name                   = "id-${var.name}-cicd"
  parent_id              = azapi_resource.rg_identity[0].id
  location               = var.location
  tags                   = var.tags
  response_export_values = ["properties.principalId", "properties.clientId"]
}

resource "azapi_resource" "cicd_federation" {
  count     = var.github_oidc == null ? 0 : 1
  type      = "Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31"
  name      = "github-${replace(var.github_oidc.repository, "/", "-")}-${var.github_oidc.environment}"
  parent_id = azapi_resource.cicd_identity[0].id

  body = {
    properties = {
      audiences = ["api://AzureADTokenExchange"]
      issuer    = "https://token.actions.githubusercontent.com"
      subject   = "repo:${var.github_oidc.repository}:environment:${var.github_oidc.environment}"
    }
  }
}

resource "azurerm_role_assignment" "cicd" {
  count                = var.github_oidc == null ? 0 : 1
  scope                = local.subscription_scope
  role_definition_name = var.github_oidc.role_definition_name
  principal_id         = azapi_resource.cicd_identity[0].output.properties.principalId
  principal_type       = "ServicePrincipal"
  description          = "LZ ${var.name} - CI/CD GitHub"
}

#------------------------------------------------------------------------------
# Budget
#------------------------------------------------------------------------------
resource "azurerm_consumption_budget_subscription" "this" {
  count           = var.budget == null ? 0 : 1
  name            = "budget-${var.name}"
  subscription_id = local.subscription_scope
  amount          = var.budget.amount
  time_grain      = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget.contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget.contact_emails
  }

  lifecycle {
    ignore_changes = [time_period]
  }
}
