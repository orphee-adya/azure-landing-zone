terraform {
  required_version = ">= 1.9.0"

  required_providers {
    alz = {
      source  = "Azure/alz"
      version = ">= 0.17, < 1.0" # aligner sur la contrainte du module avm-ptn-alz retenu
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.13"
    }
  }

  # Configuration partielle : injectée par la CI (-backend-config)
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id = var.subscription_ids.management
  features {}
}

provider "azapi" {}

# Bibliothèque ALZ locale (lib/) : dépend de la bibliothèque officielle
# platform/alz (version figée dans lib/alz_library_metadata.json) et
# surcharge l'architecture (noms des management groups).
provider "alz" {
  library_overwrite_enabled = true
  library_references = [
    {
      custom_url = "${path.root}/lib"
    }
  ]
}
