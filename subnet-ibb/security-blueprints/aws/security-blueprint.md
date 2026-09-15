# Subnet — AWS Security Blueprint

- **Scope:** subnet on aws
- **Paired Technical Reference Design:** `reference-designs/aws/reference-design.md@0.1.0`
- **Status:** draft
- **Owner:** cloud-foundations

## Controls

| ID | Domain | Requirement | Priority | Rationale | Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AWS-001 | Identity & Access | Pipeline assumes a scoped IAM role via OIDC federation, restricted to `ec2:CreateSubnet`, `ec2:DeleteSubnet`, `ec2:ModifySubnetAttribute`, `ec2:Describe*`, `ec2:CreateNetworkAcl*`, `ec2:DeleteNetworkAcl*` on this capability's tagged resources only — no static AWS credentials, no wildcard resource scope. | Critical | A broadly-scoped or static credential could create or delete network segments across any VPC in the account, enabling lateral-movement paths or accidental outages far beyond this capability's intended blast radius. | Pipeline OIDC/role-trust configuration review (not plan-time checkable) + IAM policy diff review at role-provisioning time. | Implemented |
| AWS-002 | Network Security | A subnet with `networkExposure: public` is associated only with a route table carrying a default route to the parent VPC's Internet Gateway; a `private` subnet is associated only with a route table that has no default internet route. | Critical | Associating a private-intent subnet with a public route table by mistake would silently expose workloads placed in it to the internet with no application-level warning. | `conftest` pre-apply against `policies/aws/aws-subnet.rego` (`deny_exposure_route_mismatch`), checking the planned `aws_route_table_association` against the requested `networkExposure`. | Implemented |
| AWS-003 | Data Protection | `map_public_ip_on_launch` is `true` only when `networkExposure: public`; it is always `false` for `private` subnets. | High | Auto-assigning public IPs in a subnet intended to be private would give every launched instance an internet-routable address regardless of route table configuration, defeating the exposure control above in depth. | `conftest` pre-apply against `policies/aws/aws-subnet.rego` (`deny_public_ip_on_private_subnet`). | Implemented |
| AWS-004 | Logging & Monitoring | Every `CreateSubnet`/`DeleteSubnet`/`ModifySubnetAttribute` API call is captured by the account's CloudTrail trail, and VPC Flow Logs on the parent VPC (provisioned by the `virtual-network` dependency) capture traffic to/from this subnet. | High | Without change-event and flow logging, an unauthorized or mis-scoped subnet change is invisible until a consumer notices connectivity has broken. | Post-apply live check: CloudTrail event lookup for the executing role's `CreateSubnet`/`ModifySubnetAttribute` call, recorded in pipeline evidence. | Implemented |
| AWS-005 | Network Security | A subnet with `networkAclProfile: restrictive` is associated with a dedicated NACL that allows only the parent VPC's own CIDR (plus ephemeral return traffic) and denies all else by default; `default` leaves the subnet on the VPC's baseline NACL. | Medium | Without an explicit restrictive option, workloads that need network-layer isolation beyond security groups (e.g. regulated workloads) have no self-service path to get it. | `conftest` pre-apply against `policies/aws/aws-subnet.rego` (`deny_restrictive_without_nacl`), checking a dedicated `aws_network_acl` resource exists when the profile is `restrictive`. | Implemented |
| AWS-006 | Compliance | Any request targeting `context.environment: prd` must carry a non-empty `context.changeReference`. | Medium | Production network topology changes can affect live traffic paths; an approved change record gives incident responders a starting point when a subnet change is implicated in an outage. | Pipeline authorization stage rejects `prd` requests with no `changeReference` before any Terraform run (not plan-time checkable via Terraform, since it depends on request context, not resource attributes). | Implemented |

## Verification

Controls above are:

1. **Implemented** in `iac/aws/` — each Terraform resource annotated with the control ID
   it satisfies (`# SBP AWS-00x`), per `ART-005`.
2. **Verified pre-apply** by policy-as-code in `policies/aws/` (`SEC-004`) for `AWS-002`,
   `AWS-003`, and `AWS-005`; `AWS-001`, `AWS-004`, and `AWS-006` are not plan-time checkable (they
   depend on pipeline/account configuration or request context rather than Terraform resource
   attributes) and are instead verified as described in their Verification Method column.
3. **Verified post-apply** by the pipeline re-checking live resource state, not just the Terraform
   plan — a successful `apply` is not evidence of conformance on its own (`SEC-005`).
