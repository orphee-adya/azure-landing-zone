variable "billing_scope_id" {
  description = <<-EOT
    Scope de facturation pour la création de souscriptions :
      EA  : /providers/Microsoft.Billing/billingAccounts/<id>/enrollmentAccounts/<id>
      MCA : /providers/Microsoft.Billing/billingAccounts/<id>/billingProfiles/<id>/invoiceSections/<id>
    L'identité apply doit y avoir le rôle "Subscription Creator" (EA) ou
    "Azure subscription creator" (MCA) — attribution manuelle, cf. README.
  EOT
  type        = string
  default     = null
}

variable "landing_zones_path" {
  description = "Dossier des définitions YAML de landing zones."
  type        = string
  default     = "landing-zones"
}
