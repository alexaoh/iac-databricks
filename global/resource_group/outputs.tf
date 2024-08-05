output "name" {
  value = azurerm_resource_group.this.name
}

output "id" {
  value = azurerm_resource_group.this.id
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "tags" {
  value = azurerm_resource_group.this.tags
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

