zones             = ["1", "2", "3"]
hub_address_space = "10.0.0.0/22"

hub_subnets = {
  firewall     = "10.0.0.0/26"
  gateway      = "10.0.0.64/27"
  bastion      = "10.0.0.128/26"
  dns_inbound  = "10.0.1.0/28"
  dns_outbound = "10.0.1.16/28"
}

internal_address_ranges = ["10.0.0.0/8"]
identity_address_space  = "10.0.4.0/24"
spoke_supernets         = ["10.0.4.0/24", "10.1.0.0/16"]

firewall_sku_tier       = "Premium"
ddos_protection_enabled = false # aligner avec stages/00-governance/terraform.tfvars
bastion_enabled         = true
vpn_gateway_enabled     = false
vpn_gateway_sku         = "VpnGw2AZ"

dns_resolver_enabled = true
dns_forwarding_rules = {
  # "corp.contoso.local." = ["192.168.0.10", "192.168.0.11"]
}
