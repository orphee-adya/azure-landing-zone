###############################################################################
# STAGE 50 — Subscription vending (GitOps)
# Chaque fichier landing-zones/*.yaml = une landing zone applicative.
# Une équipe demande une LZ via l'issue template -> PR ajoutant un YAML ->
# revue plateforme/réseau/FinOps -> merge -> la CD livre la souscription.
###############################################################################

module "conventions" {
  source           = "../../modules/conventions"
  org              = var.org
  location_short   = var.location_short
  subscription_ids = var.subscription_ids
  tags             = var.tags
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

  lz_files = fileset("${path.module}/${var.landing_zones_path}", "*.yaml")

  landing_zones = {
    for f in local.lz_files :
    trimsuffix(f, ".yaml") => yamldecode(file("${path.module}/${var.landing_zones_path}/${f}"))
  }

  allowed_archetypes = ["corp", "online", "sandbox", "decommissioned"]
}

check "archetypes" {
  assert {
    condition     = alltrue([for k, lz in local.landing_zones : contains(local.allowed_archetypes, lz.archetype)])
    error_message = "archetype doit être l'une des valeurs : ${join(", ", local.allowed_archetypes)}."
  }
}

module "landing_zone" {
  source   = "../../modules/landing-zone"
  for_each = local.landing_zones

  providers = {
    azurerm     = azurerm
    azurerm.hub = azurerm.connectivity
    azapi       = azapi
  }

  name             = each.key
  location         = try(each.value.location, var.location)
  location_short   = var.location_short
  billing_scope_id = var.billing_scope_id

  subscription = {
    display_name = each.value.subscription.display_name
    workload     = try(each.value.subscription.workload, "Production")
    existing_id  = try(each.value.subscription.existing_id, null)
  }

  management_group_id = module.conventions.management_group_ids[each.value.archetype]

  # Sandbox : jamais raccordée au hub (isolation)
  network = try(each.value.network, null) == null ? null : {
    address_space  = each.value.network.address_space
    connect_to_hub = each.value.archetype == "sandbox" ? false : try(each.value.network.connect_to_hub, true)
    subnets        = { for k, s in each.value.network.subnets : k => { address_prefix = s.address_prefix } }
  }

  hub = {
    vnet_id             = local.hub.hub_vnet_id
    vnet_name           = local.hub.hub_vnet_name
    resource_group_name = local.hub.hub_resource_group_name
    firewall_private_ip = local.hub.firewall_private_ip
    use_remote_gateways = local.hub.vpn_gateway_enabled
  }

  role_assignments = try(each.value.role_assignments, {})
  github_oidc      = try(each.value.github_oidc, null)
  budget           = try(each.value.budget, null)

  tags = merge(module.conventions.tags, try(each.value.tags, {}), {
    landing-zone = each.key
    archetype    = each.value.archetype
  })
}
