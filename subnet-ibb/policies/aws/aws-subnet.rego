package subnet.aws

import future.keywords.in

# Policy-as-code gate run PRE-apply against the Terraform plan (SEC-004). Each deny rule cites the
# Security Blueprint control ID it enforces (security-blueprints/aws/security-blueprint.md).

# SBP AWS-002 (defense in depth) — the route table this subnet associates with is resolved by a
# data.aws_route_table lookup filtered on tag:Tier == networkExposure (main.tf), so a mismatched
# association cannot occur without also changing that filter; this rule instead guards the input
# value itself, rejecting anything outside the agnostic contract's enum even if a caller somehow
# bypassed schema validation upstream. The route table's actual live tag is confirmed post-apply
# (security-blueprints/aws/security-blueprint.md AWS-002 Verification Method).
deny[msg] {
	not input.variables.network_exposure.value in {"private", "public"}
	msg := sprintf("SBP AWS-002: networkExposure %q is outside the approved private/public set", [input.variables.network_exposure.value])
}

# SBP AWS-003 — map_public_ip_on_launch must exactly mirror the requested networkExposure.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "aws_subnet"
	expected := input.variables.network_exposure.value == "public"
	rc.change.after.map_public_ip_on_launch != expected
	msg := sprintf("SBP AWS-003: map_public_ip_on_launch (%v) does not match requested networkExposure (%q)", [rc.change.after.map_public_ip_on_launch, input.variables.network_exposure.value])
}

# SBP AWS-005 — networkAclProfile: restrictive must produce a dedicated aws_network_acl resource.
deny[msg] {
	input.variables.network_acl_profile.value == "restrictive"
	not any_restrictive_nacl_planned
	msg := "SBP AWS-005: networkAclProfile is restrictive but no aws_network_acl resource is planned"
}

any_restrictive_nacl_planned {
	rc := input.resource_changes[_]
	rc.type == "aws_network_acl"
	rc.change.actions[_] == "create"
}

# SBP AWS-005 (defense in depth) — reject networkAclProfile values outside the agnostic contract's
# enum even if a caller somehow bypassed schema validation upstream.
deny[msg] {
	not input.variables.network_acl_profile.value in {"default", "restrictive"}
	msg := sprintf("SBP AWS-005: networkAclProfile %q is outside the approved default/restrictive set", [input.variables.network_acl_profile.value])
}
