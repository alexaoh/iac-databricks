output "metastore_id" {
  value = databricks_metastore.this.id
}

output "databricks_access_connector_id" {
  value = azurerm_databricks_access_connector.this.id
}

output "databricks_access_connector_name" {
  value = azurerm_databricks_access_connector.this.name
}

output "databricks_account_level_user_group_name" {
  value = databricks_group.account_level_user_group.display_name
}
