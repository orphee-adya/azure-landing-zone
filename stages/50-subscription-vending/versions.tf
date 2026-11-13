terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.50"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
  }

  backend "azurerm" {}
}

# Provider "neutre" (scopes explicites : alias, MG, RBAC, budgets)
provider "azurerm" {
  subscription_id                 = var.subscription_ids.management
  resource_provider_registrations = "none"
  features {}
}

provider "azurerm" {
  alias                           = "connectivity"
  subscription_id                 = var.subscription_ids.connectivity
  resource_provider_registrations = "none"
  features {}
}

provider "azapi" {}
