variable "name" {
  description = "Nom du VNet spoke."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group du spoke (existant)."
  type        = string
}

variable "location" {
  description = "Région."
  type        = string
}

variable "address_space" {
  description = "Plages d'adresses du spoke."
  type        = list(string)
}

variable "dns_servers" {
  description = "Serveurs DNS (IP privée du pare-feu en proxy DNS)."
  type        = list(string)
}

variable "firewall_private_ip" {
  description = "IP privée du pare-feu (next hop 0.0.0.0/0)."
  type        = string
}

variable "subnets" {
  description = "Sous-réseaux et règles NSG."
  type = map(object({
    address_prefix = string
    security_rules = optional(map(object({
      priority                   = number
      direction                  = string
      access                     = string
      protocol                   = string
      source_address_prefixes    = list(string)
      destination_address_prefix = string
      destination_port_ranges    = list(string)
    })), {})
  }))
}

variable "hub_vnet_id" {
  type = string
}

variable "hub_vnet_name" {
  type = string
}

variable "hub_resource_group_name" {
  type = string
}

variable "use_remote_gateways" {
  description = "Utiliser la passerelle VPN/ER du hub."
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
