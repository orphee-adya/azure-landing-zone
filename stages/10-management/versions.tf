terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
  }

  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id     = var.subscription_ids.management
  storage_use_azuread = true
  features {}
}
