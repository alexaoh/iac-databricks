terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.110.0"
    }
  }
  backend "azurerm" {
    key = "global/storage_account.tfstate"
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

resource "azurerm_storage_account" "this" {
  name                          = var.storage_account_name
  resource_group_name           = data.terraform_remote_state.rg.outputs.name
  location                      = data.terraform_remote_state.rg.outputs.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  account_kind                  = "StorageV2"
  is_hns_enabled                = "true"
  access_tier                   = "Cool"
  public_network_access_enabled = true
  tags                          = data.terraform_remote_state.rg.outputs.tags
}

resource "azurerm_storage_container" "this" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.this.name
  container_access_type = "private"
}
