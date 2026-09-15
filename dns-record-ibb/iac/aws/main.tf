locals {
  common_tags = {
    "ibb:name"            = "dns-record"
    "ibb:version"         = "0.1.0"
    "app:id"              = var.application_id
    "app:environment"     = var.environment
    "data:classification" = var.data_classification
  }
}

# SBP AWS-002: the hosted zone allow-list is enforced pre-apply by policies/aws/aws-dns-record.rego
# against the planned record's FQDN. This lookup itself only succeeds for zones that exist and are
# reachable by the pipeline's scoped IAM role (SBP AWS-001) — it does not create or modify the zone.
data "aws_route53_zone" "this" {
  name         = var.dns_zone
  private_zone = false
}

# SBP AWS-001: all changes to this record set happen only under the pipeline's scoped IAM role,
# limited to this resource type and the allow-listed zone (enforced outside Terraform, at role
# and policy level — see security-blueprints/aws/security-blueprint.md AWS-001).
resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.this.zone_id
  name    = "${var.record_name}.${var.dns_zone}"
  type    = var.record_type
  ttl     = var.ttl_seconds
  records = var.record_values
}
