variable "name" {
  description = "Identifiant court de la landing zone (ex : app1-prod)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]{3,30}$", var.name))
    error_message = "name : 3 à 30 caractères [a-z0-9-]."
  }
}

variable "location" {
  type = string
}

variable "location_short" {
  type = string
}

variable "billing_scope_id" {
  description = "Scope de facturation (EA enrollment account ou MCA invoice section) pour créer les souscriptions."
  type        = string
  default     = null
}

variable "subscription" {
  description = "Souscription à créer (display_name/workload) ou à adopter (existing_id)."
  type = object({
    display_name = string
    workload     = optional(string, "Production")
    existing_id  = optional(string)
  })
}

variable "management_group_id" {
  description = "ID ARM complet du MG cible (Corp, Online, Sandbox...)."
  type        = string
}

variable "resource_providers" {
  description = "Resource providers à enregistrer."
  type        = list(string)
  default = [
    "Microsoft.Network",
    "Microsoft.ManagedIdentity",
    "Microsoft.Insights",
    "Microsoft.OperationalInsights",
    "Microsoft.Security",
    "Microsoft.PolicyInsights",
    "Microsoft.GuestConfiguration",
    "Microsoft.KeyVault",
    "Microsoft.Storage",
    "Microsoft.Compute",
  ]
}

variable "network" {
  description = "Spoke réseau (null = pas de réseau)."
  type = object({
    address_space  = list(string)
    connect_to_hub = optional(bool, true)
    subnets = map(object({
      address_prefix = string
    }))
  })
  default = null
}

variable "hub" {
  description = "Informations du hub (issues de l'état 30-connectivity)."
  type = object({
    vnet_id             = string
    vnet_name           = string
    resource_group_name = string
    firewall_private_ip = string
    use_remote_gateways = bool
  })
}

variable "role_assignments" {
  description = "RBAC de l'équipe applicative au scope de la souscription."
  type = map(object({
    principal_id         = string
    role_definition_name = string
    principal_type       = optional(string, "Group")
  }))
  default = {}
}

variable "github_oidc" {
  description = "Identité CI/CD fédérée pour le dépôt de l'équipe applicative."
  type = object({
    repository           = string # owner/repo
    environment          = string # environnement GitHub autorisé
    role_definition_name = optional(string, "Contributor")
  })
  default = null
}

variable "budget" {
  description = "Budget mensuel (null = aucun)."
  type = object({
    amount         = number
    contact_emails = list(string)
  })
  default = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
