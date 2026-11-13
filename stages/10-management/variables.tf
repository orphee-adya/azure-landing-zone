variable "law_retention_days" {
  description = "Rétention interactive du Log Analytics plateforme (30 à 730 jours)."
  type        = number
  default     = 90
}

variable "law_daily_quota_gb" {
  description = "Quota journalier d'ingestion (-1 = illimité). Garde-fou FinOps."
  type        = number
  default     = -1
}

variable "archive_retention_days" {
  description = "Durée de conservation des journaux archivés en stockage (ex : 1825 = 5 ans)."
  type        = number
  default     = 1095
}

variable "archive_exported_tables" {
  description = "Tables Log Analytics exportées en continu vers le stockage d'archive."
  type        = list(string)
  default     = ["AzureActivity"]
}

variable "service_health_regions" {
  description = "Régions surveillées par l'alerte Service Health."
  type        = list(string)
  default     = ["France Central", "France South", "Global"]
}
