package subnet.azure

import future.keywords.in

# Policy-as-code gate run PRE-apply against the Terraform plan (SEC-004). Each deny rule cites the
# Security Blueprint control ID it enforces (security-blueprints/azure/security-blueprint.md).

# SBP AZR-002 — the NSG's outbound internet rule must exactly mirror the requested networkExposure:
# Allow for public, Deny for private.
deny[msg] {
	rc := input.resource_changes[_]
	rc.type == "azurerm_network_security_group"
	rule := rc.change.after.security_rule[_]
	rule.name == "AllowInternetOutbound"
	expected := input.variables.network_exposure.value == "public" ? "Allow" : "Deny"
	rule.access != expected
	msg := sprintf("SBP AZR-002: AllowInternetOutbound access (%q) does not match requested networkExposure (%q)", [rule.access, input.variables.network_exposure.value])
}

# SBP AZR-003 — a private subnet's route table must not carry a default (0.0.0.0/0) route to the
# Internet next-hop type.
deny[msg] {
	input.variables.network_exposure.value == "private"
	rc := input.resource_changes[_]
	rc.type == "azurerm_route_table"
	route := rc.change.after.route[_]
	route.address_prefix == "0.0.0.0/0"
	route.next_hop_type == "Internet"
	msg := "SBP AZR-003: private subnet's route table must not carry a default route to the Internet next hop"
}

# SBP AZR-005 — networkAclProfile: restrictive must produce a dedicated NSG scoping the VNet-inbound
# rule to the parent VNet's own address space rather than the platform "VirtualNetwork" alias.
deny[msg] {
	input.variables.network_acl_profile.value == "restrictive"
	rc := input.resource_changes[_]
	rc.type == "azurerm_network_security_group"
	rule := rc.change.after.security_rule[_]
	rule.name == "AllowVnetInbound"
	rule.source_address_prefix == "VirtualNetwork"
	msg := "SBP AZR-005: networkAclProfile is restrictive but the NSG's inbound rule still uses the platform VirtualNetwork alias instead of an explicit address prefix"
}

# SBP AZR-002/AZR-005 (defense in depth) — reject values outside the agnostic contract's enums
# even if a caller somehow bypassed schema validation upstream.
deny[msg] {
	not input.variables.network_exposure.value in {"private", "public"}
	msg := sprintf("SBP AZR-002: networkExposure %q is outside the approved private/public set", [input.variables.network_exposure.value])
}

deny[msg] {
	not input.variables.network_acl_profile.value in {"default", "restrictive"}
	msg := sprintf("SBP AZR-005: networkAclProfile %q is outside the approved default/restrictive set", [input.variables.network_acl_profile.value])
}
