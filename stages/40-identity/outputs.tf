output "identity_vnet_id" {
  value = module.identity_spoke.vnet_id
}

output "identity_subnet_ids" {
  value = module.identity_spoke.subnet_ids
}
