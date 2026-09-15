package compute_instance.aws

import future.keywords.in

# Policy-as-code gate run PRE-apply against the Terraform plan (SEC-004). Each deny rule cites the
# Security Blueprint control ID it enforces (security-blueprints/aws/security-blueprint.md).

# SBP AWS-002 — the root EBS volume must always be encrypted, and must use the supplied
# customer-managed key when encryptionRequired is true.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	rc.change.after.root_block_device[_].encrypted != true
	msg := "SBP AWS-002: root_block_device.encrypted must be true"
}

deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	input.variables.encryption_required.value == true
	kms_key := rc.change.after.root_block_device[_].kms_key_id
	kms_key == ""
	msg := "SBP AWS-002: encryptionRequired is true but no customer-managed kms_key_id is set on the root volume"
}

# SBP AWS-003 — IMDSv2 must be enforced unconditionally.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	opts := rc.change.after.metadata_options[_]
	opts.http_tokens != "required"
	msg := sprintf("SBP AWS-003: metadata_options.http_tokens (%q) must be \"required\"", [opts.http_tokens])
}

deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	opts := rc.change.after.metadata_options[_]
	opts.http_put_response_hop_limit != 1
	msg := sprintf("SBP AWS-003: metadata_options.http_put_response_hop_limit (%v) must be 1", [opts.http_put_response_hop_limit])
}

# SBP AWS-004 — associate_public_ip_address must exactly mirror the requested networkExposure.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	expected := input.variables.network_exposure.value == "public"
	rc.change.after.associate_public_ip_address != expected
	msg := sprintf("SBP AWS-004: associate_public_ip_address (%v) does not match requested networkExposure (%q)", [rc.change.after.associate_public_ip_address, input.variables.network_exposure.value])
}

# SBP AWS-004 (defense in depth) — reject networkExposure values outside the agnostic contract's
# enum even if a caller somehow bypassed schema validation upstream.
deny[msg] {
	not input.variables.network_exposure.value in {"private", "public"}
	msg := sprintf("SBP AWS-004: networkExposure %q is outside the approved private/public set", [input.variables.network_exposure.value])
}

# SBP AWS-005 — securityGroupProfile: restrictive must produce a dedicated aws_security_group
# resource with an ingress rule scoped only to the target subnet's own CIDR.
deny[msg] {
	input.variables.security_group_profile.value == "restrictive"
	not any_restrictive_sg_planned
	msg := "SBP AWS-005: securityGroupProfile is restrictive but no dedicated aws_security_group with a subnet-scoped ingress rule is planned"
}

any_restrictive_sg_planned {
	rc := input.resource_changes[_]
	rc.type == "aws_security_group"
	rc.change.actions[_] == "create"
	count(rc.change.after.ingress) > 0
}

# SBP AWS-005 (defense in depth) — reject securityGroupProfile values outside the agnostic
# contract's enum.
deny[msg] {
	not input.variables.security_group_profile.value in {"default", "restrictive"}
	msg := sprintf("SBP AWS-005: securityGroupProfile %q is outside the approved default/restrictive set", [input.variables.security_group_profile.value])
}

# SBP AWS-006 — disable_api_termination must exactly mirror the requested terminationProtection.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_instance"
	rc.change.after.disable_api_termination != input.variables.termination_protection.value
	msg := sprintf("SBP AWS-006: disable_api_termination (%v) does not match requested terminationProtection (%v)", [rc.change.after.disable_api_termination, input.variables.termination_protection.value])
}
