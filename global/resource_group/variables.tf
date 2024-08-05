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

variable "resource_group_location" {
  type        = string
  description = "Location of the Azure resources."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group we want to provision."
}

variable "resource_group_tags" {
  type        = map(string)
  description = "Tags for the resourece group."
  default = {
    "ManagedBy" = "Terraform"
  }
}
