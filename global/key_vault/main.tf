terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.110.0"
    }
  }
  backend "azurerm" {
    key = "global/key_vault.tfstate"
  }

}

provider "azurerm" {
  features {}
}

data "terraform_remote_state" "rg" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "global/resource_group.tfstate"
  }
}

resource "azurerm_key_vault" "this" {
  name                = var.key_vault_name
  location            = data.terraform_remote_state.rg.outputs.location
  resource_group_name = data.terraform_remote_state.rg.outputs.name
  tags                = data.terraform_remote_state.rg.outputs.tags
  tenant_id           = data.terraform_remote_state.rg.outputs.tenant_id
  sku_name            = "standard"
}
