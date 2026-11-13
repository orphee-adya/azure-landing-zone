variable "org" {
  description = "Préfixe de l'organisation (minuscules/chiffres, 2 à 10 caractères)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{2,10}$", var.org))
    error_message = "org doit contenir 2 à 10 caractères [a-z0-9]."
  }
}

variable "location_short" {
  description = "Code court de la région (ex : frc pour francecentral)."
  type        = string
}

variable "subscription_ids" {
  description = "IDs des 4 souscriptions plateforme."
  type = object({
    management   = string
    connectivity = string
    identity     = string
    security     = string
  })
}

variable "tags" {
  description = "Tags additionnels fusionnés avec les tags par défaut."
  type        = map(string)
  default     = {}
}
