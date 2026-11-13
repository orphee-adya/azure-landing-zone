###############################################################################
# Variables communes — fichier IDENTIQUE dans chaque stage (valeurs dans
# config/common.tfvars). Ne pas modifier ici sans propager aux autres stages.
###############################################################################

variable "org" {
  description = "Préfixe de l'organisation (2 à 10 caractères [a-z0-9])."
  type        = string
}

variable "location" {
  description = "Région Azure principale."
  type        = string
  default     = "francecentral"
}

variable "location_short" {
  description = "Code court de la région."
  type        = string
  default     = "frc"
}

variable "subscription_ids" {
  description = "IDs des souscriptions plateforme."
  type = object({
    management   = string
    connectivity = string
    identity     = string
    security     = string
  })
}

variable "tfstate" {
  description = "Backend d'état partagé (lecture des états des autres stages)."
  type = object({
    subscription_id      = string
    resource_group_name  = string
    storage_account_name = string
    container_name       = string
  })
}

variable "platform_contact_email" {
  description = "Adresse e-mail de l'équipe plateforme (alertes, Defender)."
  type        = string
}

variable "tags" {
  description = "Tags communs."
  type        = map(string)
  default     = {}
}
