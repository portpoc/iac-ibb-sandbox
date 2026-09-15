output "record_id" {
  description = "result.recordId — Route 53 record set identifier (zoneId_name_type)."
  value       = aws_route53_record.this.id
}

output "fqdn" {
  description = "result.fqdn — the record's fully-qualified domain name."
  value       = aws_route53_record.this.fqdn
}

output "tags" {
  description = "Evidence-only: the common tag set this IBB associates with the change (Route 53 record sets do not support native resource tags, so these are carried in pipeline evidence instead)."
  value       = local.common_tags
}
