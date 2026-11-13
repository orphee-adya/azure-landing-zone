variable "identity_address_space" {
  description = "Plage du spoke identité (doit correspondre à 30-connectivity)."
  type        = string
  default     = "10.0.4.0/24"
}

variable "domain_controller_subnet" {
  description = "Sous-réseau des contrôleurs de domaine."
  type        = string
  default     = "10.0.4.0/27"
}

variable "internal_address_ranges" {
  description = "Clients AD autorisés (spokes + on-prem)."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "bastion_subnet" {
  description = "AzureBastionSubnet du hub (accès d'administration RDP/SSH)."
  type        = string
  default     = "10.0.0.128/26"
}
