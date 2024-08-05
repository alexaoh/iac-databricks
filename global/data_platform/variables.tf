variable "tfstate_resource_group_name" {
  type        = string
  description = "Name of the resource group that holds the remote statefile."
}

variable "tfstate_storage_account_name" {
  type        = string
  description = "Name of the storage account that holds the remote statefile."
}

variable "tfstate_container_name" {
  type        = string
  description = "Name of the container that holds the remote statefile."
}

variable "databricks_workspace_name" {
  type        = string
  description = "Name of the Databricks Workspace we want to provision."
}

variable "databricks_account_id" {
  type        = string
  description = "Databricks account ID. Necessary to set up the account-level Databricks Terraform provider."
}
