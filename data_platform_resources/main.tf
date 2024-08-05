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
    key = "data_platform_resources.tfstate"
  }

}

# This provider is used for authentication to Databricks (through the workspace-level provider below) by sharing the authentication configuration of azurem. 
provider "azurerm" {
  features {}
}

# Workspace-level provider.
provider "databricks" {
  host = data.terraform_remote_state.databricks_workspace.outputs.workspace_url
}

data "terraform_remote_state" "databricks_workspace" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = var.tfstate_container_name
    key                  = "global/data_platform.tfstate"
  }
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

# Get latest spark version. It is necessary to add the 'depends_on' below for authentication: 
data "databricks_spark_version" "latest" {}

# Get smallest node type with local disk storage.
data "databricks_node_type" "smallest" {
  local_disk = true
}

# Create resources below! https://registry.terraform.io/providers/databricks/databricks/latest/docs/guides/workspace-management

# E.g. create a cluster (not unity catalog enabled by default when defined as below).
resource "databricks_cluster" "this" {
  cluster_name            = "Exploration"
  spark_version           = data.databricks_spark_version.latest.id
  node_type_id            = data.databricks_node_type.smallest.id
  autotermination_minutes = 10
  autoscale {
    min_workers = 1
    max_workers = 2
  }
}

# E.g. create a workflow job
# resource "databricks_job" "this" {
#   name = "ELT following Medallion 'Architecture'"

#   task {
#     task_key        = "0_source_to_bronze"
#     job_cluster_key = "smallest-job-specific"

#     notebook_task {
#       notebook_path = "insert_path_here"
#       source        = "GIT"
#     }
#   }

#   task {
#     task_key        = "1_bronze_to_silver"
#     job_cluster_key = "smallest-job-specific"

#     notebook_task {
#       notebook_path = "insert_path_here"
#       source        = "GIT"
#     }

#     depends_on {
#       task_key = "0_source_to_bronze"
#     }
#   }

#   job_cluster {
#     job_cluster_key = "smallest-job-specific"
#     new_cluster {
#       num_workers   = 1
#       spark_version = data.databricks_spark_version.latest.id
#       node_type_id  = data.databricks_node_type.smallest.id
#     }
#   }

#   git_source {
#     url      = "insert URL here"
#     provider = "gitHub"
#     branch   = "main"
#   }

#   tags = data.terraform_remote_state.rg.outputs.tags

# }
