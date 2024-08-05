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
