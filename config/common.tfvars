###############################################################################
# Variables communes à TOUS les stages (passées via -var-file par la CI).
# Les variables spécifiques à un stage sont dans stages/<stage>/terraform.tfvars
###############################################################################

org            = "contoso" # doit correspondre aux IDs dans stages/00-governance/lib (cf. scripts/rename-org.sh)
location       = "francecentral"
location_short = "frc"

subscription_ids = {
  management   = "00000000-0000-0000-0000-000000000001"
  connectivity = "00000000-0000-0000-0000-000000000002"
  identity     = "00000000-0000-0000-0000-000000000003"
  security     = "00000000-0000-0000-0000-000000000004"
}

# Backend d'état (créé par bootstrap/) — utilisé par les data terraform_remote_state
tfstate = {
  subscription_id      = "00000000-0000-0000-0000-000000000001"
  resource_group_name  = "rg-contoso-tfstate-frc"
  storage_account_name = "stcontosotfstatefrc"
  container_name       = "tfstate"
}

platform_contact_email = "cloud-platform@contoso.fr"

tags = {
  owner       = "platform-team"
  cost-center = "IT-CLOUD"
  environment = "platform"
}
