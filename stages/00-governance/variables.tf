variable "alz_architecture_name" {
  description = "Nom de l'architecture définie dans lib/architecture_definitions."
  type        = string
  default     = "landing_zone"
}

variable "allowed_locations" {
  description = "Régions autorisées (policy Deny à la racine). 'global' est ajouté automatiquement pour les ressources non régionales."
  type        = list(string)
  default     = ["francecentral", "francesouth", "westeurope"]
}

variable "ddos_protection_enabled" {
  description = "Doit être aligné avec 30-connectivity. Si false, la policy Enable-DDoS-VNET passe en DoNotEnforce."
  type        = bool
  default     = false
}

variable "rbac_assignments" {
  description = <<-EOT
    Affectations RBAC de groupes Entra ID sur les management groups.
    management_group : clé du module conventions (root, platform, connectivity, security, landing_zones, corp, ...).
  EOT
  type = map(object({
    principal_id         = string
    role_definition_name = string
    management_group     = string
  }))
  default = {}
}

variable "enable_telemetry" {
  description = "Télémétrie AVM (usage anonyme des modules Microsoft)."
  type        = bool
  default     = false
}
