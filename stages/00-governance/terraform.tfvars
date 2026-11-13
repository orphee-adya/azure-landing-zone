allowed_locations       = ["francecentral", "francesouth", "westeurope"]
ddos_protection_enabled = false

# Groupes Entra ID (object IDs) — à créer au préalable (PIM recommandé)
rbac_assignments = {
  # platform_admins = {
  #   principal_id         = "00000000-0000-0000-0000-000000000000"
  #   role_definition_name = "Owner"
  #   management_group     = "platform"
  # }
  # network_ops = {
  #   principal_id         = "00000000-0000-0000-0000-000000000000"
  #   role_definition_name = "Network Contributor"
  #   management_group     = "connectivity"
  # }
  # secops = {
  #   principal_id         = "00000000-0000-0000-0000-000000000000"
  #   role_definition_name = "Security Admin"
  #   management_group     = "root"
  # }
  # auditors = {
  #   principal_id         = "00000000-0000-0000-0000-000000000000"
  #   role_definition_name = "Reader"
  #   management_group     = "root"
  # }
}
