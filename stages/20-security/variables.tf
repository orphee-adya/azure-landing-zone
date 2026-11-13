variable "sentinel_retention_days" {
  description = "Rétention du workspace Sentinel (90 jours inclus sans surcoût Sentinel)."
  type        = number
  default     = 90
}

variable "entra_diagnostics_enabled" {
  description = <<-EOT
    Exporter les journaux Entra ID vers Sentinel. Nécessite que l'identité
    apply ait le rôle Entra "Security Administrator" (ou que ce paramétrage
    soit fait une fois manuellement) — désactivé par défaut.
  EOT
  type        = bool
  default     = false
}

variable "entra_log_categories" {
  description = "Catégories de journaux Entra ID exportées."
  type        = list(string)
  default = [
    "AuditLogs",
    "SignInLogs",
    "NonInteractiveUserSignInLogs",
    "ServicePrincipalSignInLogs",
    "ManagedIdentitySignInLogs",
    "ProvisioningLogs",
    "RiskyUsers",
    "UserRiskEvents",
    "RiskyServicePrincipals",
    "ServicePrincipalRiskEvents",
    "MicrosoftGraphActivityLogs",
  ]
}

variable "key_vault_allowed_ips" {
  description = "IP publiques autorisées sur le Key Vault de sécurité (vide = private endpoint uniquement)."
  type        = list(string)
  default     = []
}
