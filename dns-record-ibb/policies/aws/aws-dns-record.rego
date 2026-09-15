package dns_record.aws

import future.keywords.in

# Policy-as-code gate run PRE-apply against the Terraform plan (SEC-004). Each deny rule cites the
# Security Blueprint control ID it enforces (security-blueprints/aws/security-blueprint.md).

# Hosted zones this capability is permitted to write records into. Extend via PR reviewed by
# platform-networking (CODEOWNERS) — this is a deliberate allow-list, not open configuration.
allowed_zone_suffixes := {"example.com.", "internal.example.com."}

# SBP AWS-002 — deny any record whose FQDN does not fall under an allow-listed hosted zone.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_route53_record"
	not zone_allowed(rc.change.after.name)
	msg := sprintf("SBP AWS-002: record %q is not in an approved hosted zone allow-list", [rc.change.after.name])
}

zone_allowed(name) {
	some suffix
	allowed_zone_suffixes[suffix]
	endswith(name, suffix)
}

# SBP AWS-003 — DNS records are globally public; confidential-classified requests must never reach
# apply. dataClassification is passed as a plan variable, not a resource attribute.
deny[msg] {
	input.variables.data_classification.value == "confidential"
	msg := "SBP AWS-003: dns-record cannot be used for context.dataClassification: confidential — Route 53 records are globally public"
}

# SBP AWS-002 (defense in depth) — reject record types outside the agnostic contract's enum even
# if a caller somehow bypassed schema validation upstream.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_route53_record"
	not rc.change.after.type in {"A", "CNAME", "TXT"}
	msg := sprintf("SBP AWS-002: record type %q is outside the approved A/CNAME/TXT set", [rc.change.after.type])
}
