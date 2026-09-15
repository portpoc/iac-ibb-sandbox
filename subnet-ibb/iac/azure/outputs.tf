output "subnet_id" {
  description = "result.subnetId — Azure subnet resource id."
  value       = azurerm_subnet.this.id
}

output "cidr_block" {
  description = "result.cidrBlock — the subnet's actual allocated address prefix."
  value       = azurerm_subnet.this.address_prefixes[0]
}

output "route_table_id" {
  description = "result.routeTableId — the route table associated with this subnet."
  value       = azurerm_route_table.this.id
}

output "tags" {
  description = "Evidence-only: the common tag set this IBB associates with the change."
  value       = local.common_tags
}
