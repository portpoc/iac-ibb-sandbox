output "subnet_id" {
  description = "result.subnetId — AWS subnet identifier."
  value       = aws_subnet.this.id
}

output "cidr_block" {
  description = "result.cidrBlock — the subnet's actual allocated CIDR block."
  value       = aws_subnet.this.cidr_block
}

output "availability_zone" {
  description = "result.availabilityZone — the resolved AZ name (e.g. us-east-1a)."
  value       = aws_subnet.this.availability_zone
}

output "route_table_id" {
  description = "result.routeTableId — the route table this subnet is associated with."
  value       = data.aws_route_table.selected.id
}

output "tags" {
  description = "Evidence-only: the common tag set this IBB associates with the change."
  value       = local.common_tags
}
