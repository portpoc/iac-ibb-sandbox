output "instance_id" {
  description = "result.instanceId — AWS instance identifier."
  value       = aws_instance.this.id
}

output "private_ip" {
  description = "result.privateIp — the instance's private IP address."
  value       = aws_instance.this.private_ip
}

output "public_ip" {
  description = "result.publicIp — the instance's public IP address, empty when networkExposure is private."
  value       = aws_instance.this.public_ip
}

output "availability_zone" {
  description = "result.availabilityZone — the resolved AZ name (e.g. us-east-1a)."
  value       = aws_instance.this.availability_zone
}

output "tags" {
  description = "Evidence-only: the common tag set this IBB associates with the change."
  value       = local.common_tags
}
