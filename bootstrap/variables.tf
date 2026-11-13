variable "org" {
  description = "Préfixe de l'organisation (2 à 10 caractères [a-z0-9])."
  type        = string
}

variable "org_display_name" {
  description = "Nom affiché du management group racine intermédiaire."
  type        = string
}

variable "location" {
  description = "Région Azure."
  type        = string
  default     = "francecentral"
}

variable "location_short" {
  description = "Code court de région."
  type        = string
  default     = "frc"
}

variable "subscription_ids" {
  description = "Souscriptions plateforme (créées au préalable, cf. README §Prérequis)."
  type = object({
    management   = string
    connectivity = string
    identity     = string
    security     = string
  })
}

variable "state_storage_account_name" {
  description = "Nom du compte de stockage d'état (globalement unique). Null = st<org>tfstate<loc>."
  type        = string
  default     = null
}

variable "state_replication_type" {
  description = "Réplication du stockage d'état (ZRS recommandé ; GZRS si exigence DR inter-région)."
  type        = string
  default     = "ZRS"
}

variable "state_public_network_access_enabled" {
  description = <<-EOT
    true  : accessible depuis les runners GitHub hébergés (authentification Entra ID uniquement, clés désactivées).
    false : nécessite des runners auto-hébergés dans un VNet + private endpoint (recommandé en production sensible).
  EOT
  type        = bool
  default     = true
}

variable "github_owner" {
  description = "Organisation ou utilisateur GitHub propriétaire du dépôt."
  type        = string
}

variable "github_repository" {
  description = "Nom du dépôt (sans l'owner)."
  type        = string
}

variable "manage_github" {
  description = "Créer les environnements et variables GitHub via Terraform."
  type        = bool
  default     = true
}

variable "github_apply_reviewer_teams" {
  description = "Slugs des équipes GitHub autorisées à approuver les déploiements (environnement alz-apply)."
  type        = list(string)
  default     = ["cloud-platform-approvers"]
}

variable "github_prevent_self_review" {
  description = "Interdire à l'auteur d'un déploiement de l'approuver lui-même (mettre false si vous êtes seul à tester)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags communs."
  type        = map(string)
  default     = {}
}
