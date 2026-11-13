###############################################################################
# Module "conventions"
# Source unique de vérité pour le nommage (CAF) et les IDs déterministes.
# Permet aux stages de se référencer sans dépendance d'ordre (ex : la
# gouvernance passe l'ID du Log Analytics aux policies DINE avant même que
# le workspace n'existe ; la remédiation s'exécutera une fois créé).
###############################################################################

locals {
  o = var.org
  l = var.location_short

  # Suffixe court et stable pour les noms globalement uniques (KV, Storage)
  sfx_mgmt = substr(replace(var.subscription_ids.management, "-", ""), 0, 4)
  sfx_sec  = substr(replace(var.subscription_ids.security, "-", ""), 0, 4)

  management_groups = {
    root           = local.o
    platform       = "${local.o}-platform"
    management     = "${local.o}-management"
    connectivity   = "${local.o}-connectivity"
    identity       = "${local.o}-identity"
    security       = "${local.o}-security"
    landing_zones  = "${local.o}-landingzones"
    corp           = "${local.o}-corp"
    online         = "${local.o}-online"
    sandbox        = "${local.o}-sandbox"
    decommissioned = "${local.o}-decommissioned"
  }

  resource_groups = {
    tfstate    = "rg-${local.o}-tfstate-${local.l}"
    cicd       = "rg-${local.o}-cicd-${local.l}"
    management = "rg-${local.o}-management-${local.l}"
    security   = "rg-${local.o}-security-${local.l}"
    hub        = "rg-${local.o}-hub-${local.l}"
    dns        = "rg-${local.o}-dns-${local.l}"
    ddos       = "rg-${local.o}-ddos-${local.l}"
    identity   = "rg-${local.o}-identity-${local.l}"
  }

  names = {
    law_platform       = "law-${local.o}-platform-${local.l}"
    law_sentinel       = "law-${local.o}-sentinel-${local.l}"
    uami_ama           = "id-${local.o}-ama-${local.l}"
    dcr_vminsights     = "dcr-${local.o}-vminsights-${local.l}"
    dcr_changetracking = "dcr-${local.o}-changetracking-${local.l}"
    dcr_defendersql    = "dcr-${local.o}-defendersql-${local.l}"
    action_group       = "ag-${local.o}-platform-${local.l}"
    st_logarchive      = "st${local.o}logs${local.l}${local.sfx_mgmt}"
    kv_security        = "kv${local.o}sec${local.l}${local.sfx_sec}"
    ddos_plan          = "ddos-${local.o}-${local.l}"
    hub_vnet           = "vnet-${local.o}-hub-${local.l}"
    firewall           = "afw-${local.o}-hub-${local.l}"
    firewall_policy    = "afwp-${local.o}-hub-${local.l}"
    bastion            = "bas-${local.o}-hub-${local.l}"
    vpn_gateway        = "vgw-${local.o}-hub-${local.l}"
    dns_resolver       = "dnspr-${local.o}-hub-${local.l}"
    identity_vnet      = "vnet-${local.o}-identity-${local.l}"
  }

  rg_id = {
    management = "/subscriptions/${var.subscription_ids.management}/resourceGroups/${local.resource_groups.management}"
    ddos       = "/subscriptions/${var.subscription_ids.connectivity}/resourceGroups/${local.resource_groups.ddos}"
  }

  ids = {
    law_platform       = "${local.rg_id.management}/providers/Microsoft.OperationalInsights/workspaces/${local.names.law_platform}"
    uami_ama           = "${local.rg_id.management}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.names.uami_ama}"
    dcr_vminsights     = "${local.rg_id.management}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_vminsights}"
    dcr_changetracking = "${local.rg_id.management}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_changetracking}"
    dcr_defendersql    = "${local.rg_id.management}/providers/Microsoft.Insights/dataCollectionRules/${local.names.dcr_defendersql}"
    ddos_plan          = "${local.rg_id.ddos}/providers/Microsoft.Network/ddosProtectionPlans/${local.names.ddos_plan}"
  }

  management_group_ids = {
    for k, v in local.management_groups : k => "/providers/Microsoft.Management/managementGroups/${v}"
  }

  default_tags = merge({
    managed-by = "terraform"
    platform   = "azure-landing-zone"
  }, var.tags)
}
