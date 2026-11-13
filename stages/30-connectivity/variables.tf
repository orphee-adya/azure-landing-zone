variable "zones" {
  description = "Zones de disponibilité utilisées pour les IP publiques et le pare-feu."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "hub_address_space" {
  description = "Plage du VNet hub."
  type        = string
  default     = "10.0.0.0/22"
}

variable "hub_subnets" {
  description = "Plan d'adressage du hub (les noms Azure* et GatewaySubnet sont imposés)."
  type = object({
    firewall     = string
    gateway      = string
    bastion      = string
    dns_inbound  = string
    dns_outbound = string
  })
  default = {
    firewall     = "10.0.0.0/26"
    gateway      = "10.0.0.64/27"
    bastion      = "10.0.0.128/26"
    dns_inbound  = "10.0.1.0/28"
    dns_outbound = "10.0.1.16/28"
  }
}

variable "internal_address_ranges" {
  description = "Plages privées internes (spokes + on-prem) — sources des règles du pare-feu."
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "identity_address_space" {
  description = "Plage du spoke identité (contrôleurs de domaine) — cible des règles AD."
  type        = string
  default     = "10.0.4.0/24"
}

variable "spoke_supernets" {
  description = "Super-réseaux des spokes (routés via le pare-feu depuis la GatewaySubnet)."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.1.0.0/16"]
}

variable "firewall_sku_tier" {
  description = "Standard ou Premium (Premium = IDPS + inspection TLS, recommandé)."
  type        = string
  default     = "Premium"
  validation {
    condition     = contains(["Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier doit valoir Standard ou Premium."
  }
}

variable "ddos_protection_enabled" {
  description = "Plan DDoS Network Protection (coût élevé, mutualisable sur 100 IP publiques). Aligner avec 00-governance."
  type        = bool
  default     = false
}

variable "bastion_enabled" {
  description = "Déployer Azure Bastion (Standard) dans le hub."
  type        = bool
  default     = true
}

variable "vpn_gateway_enabled" {
  description = "Déployer une passerelle VPN site-à-site (≈ 30-45 min de déploiement)."
  type        = bool
  default     = false
}

variable "vpn_gateway_sku" {
  description = "SKU de la passerelle VPN (variantes AZ pour la redondance de zone)."
  type        = string
  default     = "VpnGw2AZ"
}

variable "dns_resolver_enabled" {
  description = "Déployer Azure DNS Private Resolver (résolution hybride on-prem <-> Azure)."
  type        = bool
  default     = true
}

variable "dns_forwarding_rules" {
  description = "Redirections conditionnelles vers des DNS on-prem : { \"corp.contoso.local.\" = [\"192.168.0.10\", \"192.168.0.11\"] }."
  type        = map(list(string))
  default     = {}
}

variable "additional_private_dns_zones" {
  description = "Zones privatelink supplémentaires."
  type        = list(string)
  default     = []
}
