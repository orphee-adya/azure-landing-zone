terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.6"
    }
  }

  # 1er run : état local. Ensuite décommenter puis `terraform init -migrate-state`
  # backend "azurerm" {
  #   subscription_id      = "<management-subscription-id>"
  #   resource_group_name  = "rg-contoso-tfstate-frc"
  #   storage_account_name = "stcontosotfstatefrc"
  #   container_name       = "tfstate"
  #   key                  = "bootstrap.tfstate"
  #   use_azuread_auth     = true
  # }
}

provider "azurerm" {
  subscription_id     = var.subscription_ids.management
  storage_use_azuread = true
  features {
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}

# Jeton lu depuis GITHUB_TOKEN (PAT fine-grained : Administration RW,
# Environments RW, Variables RW sur le dépôt) ou `gh auth token`.
provider "github" {
  owner = var.github_owner
}
