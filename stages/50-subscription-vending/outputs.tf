output "landing_zones" {
  description = "Souscriptions livrées et identités CI/CD à transmettre aux équipes."
  value = {
    for k, lz in module.landing_zone : k => {
      subscription_id = lz.subscription_id
      vnet_id         = lz.vnet_id
      cicd_client_id  = lz.cicd_client_id
    }
  }
}
