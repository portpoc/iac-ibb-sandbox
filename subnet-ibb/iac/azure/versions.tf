terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }

  # Remote state backend — org-specific values not known to this scaffold. Fill in the real
  # storage account/container/key before first apply; see scaffold-ibb SKILL.md §6.
  backend "azurerm" {
    # resource_group_name  = "REPLACE_WITH_ORG_TFSTATE_RESOURCE_GROUP"
    # storage_account_name = "REPLACE_WITH_ORG_TFSTATE_STORAGE_ACCOUNT"
    # container_name       = "tfstate"
    # key                  = "subnet-ibb/azure/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}
