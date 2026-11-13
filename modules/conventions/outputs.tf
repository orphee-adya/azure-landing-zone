output "management_groups" {
  description = "Noms (IDs courts) des management groups."
  value       = local.management_groups
}

output "management_group_ids" {
  description = "IDs ARM complets des management groups."
  value       = local.management_group_ids
}

output "resource_groups" {
  description = "Noms des resource groups plateforme."
  value       = local.resource_groups
}

output "names" {
  description = "Noms des ressources plateforme."
  value       = local.names
}

output "ids" {
  description = "IDs ARM déterministes des ressources partagées (référencées par les policies)."
  value       = local.ids
}

output "tags" {
  description = "Tags par défaut fusionnés."
  value       = local.default_tags
}
