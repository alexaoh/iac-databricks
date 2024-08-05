terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.110.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~>1.48.0"
    }
  }
  backend "azurerm" {
    key = "global/unity_catalog_metastore.tfstate"
  }

}

provider "azurerm" {
  features {}
}

# Account-level provider.
provider "databricks" {
  alias      = "account"
  host       = "https://accounts.azuredatabricks.net/"
  account_id = var.databricks_account_id
}

# Read the remote resource group state. 
data "terraform_remote_state" "rg" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "global/resource_group.tfstate"
  }
}

# Read the remote storage account state.
data "terraform_remote_state" "storage_account" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "global/storage_account.tfstate"
  }
}

# Create a Unity Catalog metastore in the given region (we assume a metastore does not already exist in the region).
resource "databricks_metastore" "this" {
  provider = databricks.account
  name     = "${var.metastore_name_prefix}-${data.terraform_remote_state.rg.outputs.location}"
  region   = data.terraform_remote_state.rg.outputs.location
}

# Create an access connector for an Azure databricks account.
resource "azurerm_databricks_access_connector" "this" {
  name                = "${var.metastore_name_prefix}-access-connector"
  resource_group_name = data.terraform_remote_state.rg.outputs.name
  location            = data.terraform_remote_state.rg.outputs.location
  tags                = data.terraform_remote_state.rg.outputs.tags
  identity {
    type = "SystemAssigned"
  }
}

# Give necessary Storage Blob Data Contributor to the system assigned managed identity of the Databricks Access Connector. 
resource "azurerm_role_assignment" "this" {
  scope                = data.terraform_remote_state.storage_account.outputs.storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

data "azurerm_client_config" "current" {}

# Create a service principal with the current user. 
resource "databricks_service_principal" "current" {
  provider       = databricks.account
  display_name   = "iac-databricks-sp-made-via-terraform"
  application_id = data.azurerm_client_config.current.object_id # I think maybe should have used client_id here? This could have saved some manual intervention I had to perform while using the CD-pipeline to deploy. 
}

# Create an account-level group.
resource "databricks_group" "account_level_user_group" {
  provider     = databricks.account
  display_name = "iac-databricks-workspace-users"
}

# Add the service principal to the group.
resource "databricks_group_member" "current" {
  provider  = databricks.account
  group_id  = databricks_group.account_level_user_group.id
  member_id = databricks_service_principal.current.id
}

# Make the group account admin.
resource "databricks_group_role" "current_account_admin" {
  provider = databricks.account
  group_id = databricks_group.account_level_user_group.id
  role     = "account_admin"
}

# resource "databricks_group_role" "current_metastore_admin" {
#   provider = databricks.account
#   group_id = databricks_group.account_level_user_group.id
#   role     = "metastore_admin" # This role is not recognized/valid. Anyway, the principal that creates the metastore is automatically set as metastore admin according to docs. 
# }
