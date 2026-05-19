output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "storage_account_name" {
  value = azurerm_storage_account.deployment.name
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "appgw_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "appgw_id" {
  value = azurerm_application_gateway.app.id
}
