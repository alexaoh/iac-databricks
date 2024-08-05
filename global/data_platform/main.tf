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
    key = "global/data_platform.tfstate"
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

# Workspace-level provider.
provider "databricks" {
  alias = "workspace"
  host  = azurerm_databricks_workspace.this.workspace_url
}

# Read remote state of resource group.
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

# Read remote state of the metastore.
data "terraform_remote_state" "unity_catalog_metastore" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "global/unity_catalog_metastore.tfstate"
  }
}

# Create a databricks workspace.
resource "azurerm_databricks_workspace" "this" {
  name                          = var.databricks_workspace_name
  resource_group_name           = data.terraform_remote_state.rg.outputs.name
  location                      = data.terraform_remote_state.rg.outputs.location
  sku                           = "premium"
  tags                          = data.terraform_remote_state.rg.outputs.tags
  public_network_access_enabled = "true"
}

# Assign the workspace to the manually provisioned metastore.
resource "databricks_metastore_assignment" "this" {
  provider             = databricks.account
  metastore_id         = data.terraform_remote_state.unity_catalog_metastore.outputs.metastore_id
  workspace_id         = azurerm_databricks_workspace.this.workspace_id
  default_catalog_name = azurerm_databricks_workspace.this.name # Use the name of the workspace as the default catalog name.
}

# Create a databricks storage credential.
resource "databricks_storage_credential" "this" {
  provider     = databricks.workspace
  name         = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_access_connector_name
  metastore_id = data.terraform_remote_state.unity_catalog_metastore.outputs.metastore_id
  azure_managed_identity {
    access_connector_id = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_access_connector_id
  }
  comment    = "Managed by TF"
  depends_on = [databricks_metastore_assignment.this]
  #isolation_mode = "ISOLATION_MODE_ISOLATED" # Cannot get this to work now, since the binding below is not created in time before the entire plan fails. Can make it work with some manual intervention in the workspace, but that is not ideal. Thus, leave OPEN for now. 
  isolation_mode = "ISOLATION_MODE_OPEN"
}

# Bind the storage credential to the given workspace. In combination with 'ISOLATION_MODE_ISOLATED' on the storage credential, this ensures that access to the storage credential only can be had via the given workspace. 
resource "databricks_catalog_workspace_binding" "storage_credential_workspace_binding" {
  provider       = databricks.workspace
  workspace_id   = azurerm_databricks_workspace.this.workspace_id
  securable_name = databricks_storage_credential.this.name
  securable_type = "storage_credential"
}

# Grant our user group CREATE EXTERNAL LOCATION privileges on the storage credential.
resource "databricks_grants" "storage_credential_create_external_location" {
  provider           = databricks.workspace
  storage_credential = databricks_storage_credential.this.id
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["CREATE_EXTERNAL_LOCATION"]
  }
}

# Create a databricks external location for the catalog_workspace_binding for workspace and storage account container below. 
resource "databricks_external_location" "this" {
  provider = databricks.workspace
  name     = "iac-databricks-external-location"
  url = format("abfss://%s@%s.dfs.core.windows.net",
    data.terraform_remote_state.storage_account.outputs.storage_container_name,
  data.terraform_remote_state.storage_account.outputs.storage_account_name)

  credential_name = databricks_storage_credential.this.name
  comment         = "Managed by TF"
  #isolation_mode  = "ISOLATION_MODE_ISOLATED"
  isolation_mode = "ISOLATION_MODE_OPEN"
  depends_on     = [databricks_catalog_workspace_binding.storage_credential_workspace_binding]
}

# Bind the external location to the given workspace. In combination with 'ISOLATION_MODE_ISOLATED' on the external location, this ensures that access to it only can be had via the given workspace. 
resource "databricks_catalog_workspace_binding" "external_location_workspace_binding" {
  provider       = databricks.workspace
  workspace_id   = azurerm_databricks_workspace.this.workspace_id
  securable_name = databricks_external_location.this.name
  securable_type = "external_location"
}

# Grant our user group CREATE MANAGED STORAGE privileges on the external location.
resource "databricks_grants" "external_location_create_managed_storage" {
  provider          = databricks.workspace
  external_location = databricks_external_location.this.id
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["CREATE_MANAGED_STORAGE"]
  }
}

# Create a catalog to hold the managed storage.
resource "databricks_catalog" "this" {
  provider = databricks.workspace
  name     = azurerm_databricks_workspace.this.name
  storage_root = format("abfss://%s@%s.dfs.core.windows.net/managed_storage_catalog_loc",
    data.terraform_remote_state.storage_account.outputs.storage_container_name,
  data.terraform_remote_state.storage_account.outputs.storage_account_name)
  comment = "Managed by TF"
  properties = {
    purpose = "Container for holding all managed storage in this workspace and metastore."
  }
  depends_on     = [databricks_catalog_workspace_binding.external_location_workspace_binding]
  isolation_mode = "ISOLATED"
}

# Bind the catalog to the given workspace. In combination with 'ISOLATION_MODE_ISOLATED' on the catalog, this ensures that access to it only can be had via the given workspace. 
resource "databricks_catalog_workspace_binding" "catalog_workspace_binding" {
  provider       = databricks.workspace
  workspace_id   = azurerm_databricks_workspace.this.workspace_id
  securable_name = databricks_catalog.this.name
  securable_type = "catalog"
}

# Grant the workspace users some privileges on the catalog. 
resource "databricks_grants" "catalog_privileges" {
  provider = databricks.workspace
  catalog  = databricks_catalog.this.name
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["USE_CATALOG", "CREATE_SCHEMA", "USE_SCHEMA", "APPLY_TAG", "BROWSE", "MODIFY", "READ_VOLUME", "SELECT", "WRITE_VOLUME"]
  }
}

# Create a schema.
resource "databricks_schema" "this" {
  provider     = databricks.workspace
  catalog_name = databricks_catalog.this.id
  name         = "iac-databricks-schema"
  comment      = "Managed by TF"
  properties = {
    purpose = "Schema inside container for holding all managed storage in this workspace and metastore."
  }
}

# Grant the workspace users some privileges on the schema. Note: privileges are inherited from parents, so this may be redundant.
resource "databricks_grants" "schema_privileges" {
  provider = databricks.workspace
  schema   = databricks_schema.this.id
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["USE_SCHEMA", "APPLY_TAG", "MODIFY", "READ_VOLUME", "SELECT", "WRITE_VOLUME", "CREATE_TABLE", "CREATE_VOLUME"]
  }
}

# Create an external volume.
resource "databricks_volume" "this" {
  provider     = databricks.workspace
  name         = "iac-databricks-ext-volume"
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.this.name
  volume_type  = "EXTERNAL"
  storage_location = format("abfss://%s@%s.dfs.core.windows.net/external_volume_loc",
    data.terraform_remote_state.storage_account.outputs.storage_container_name,
  data.terraform_remote_state.storage_account.outputs.storage_account_name)
  comment = "Managed by TF"
}

# Grant the workspace users some privileges on the volume. Note: privileges are inherited from parents, so this may be redundant.
resource "databricks_grants" "volume_privileges" {
  provider = databricks.workspace
  volume   = databricks_volume.this.id
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["WRITE_VOLUME", "APPLY_TAG", "READ_VOLUME"]
  }
}

# Create a table.
resource "databricks_sql_table" "this" {
  provider     = databricks.workspace
  name         = "quickstart_table_view"
  catalog_name = databricks_catalog.this.name
  schema_name  = databricks_schema.this.name
  table_type   = "MANAGED"
  comment      = "Managed by TF"
}

# Grant the workspace users some privileges on the table. Note: privileges are inherited from parents, so this may be redundant.
resource "databricks_grants" "table_privileges" {
  provider = databricks.workspace
  table    = databricks_sql_table.this.id
  grant {
    principal  = data.terraform_remote_state.unity_catalog_metastore.outputs.databricks_account_level_user_group_name
    privileges = ["SELECT", "MODIFY"]
  }
}

# TODO: Create a secret scope, tie it to the key vault (either backed by it, or add key vault secrets as secrets in a Databricks-backed secret sope).
