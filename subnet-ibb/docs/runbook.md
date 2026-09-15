# Subnet IBB — Operational Runbook

- **Owner:** cloud-foundations
- **Support:** cloud-foundations@dsv.com

## Support

Request help via **cloud-foundations@dsv.com**. For production-impacting network issues, page the
cloud-foundations on-call via the standard escalation route for that mailbox/team.

## Escalation

1. cloud-foundations@dsv.com — first line of support, business hours.
2. cloud-foundations on-call — for `prd` subnet outages or suspected exposure misconfiguration.
3. Security team — if a change appears to have been made outside the pipeline's scoped
   identity/role (see SBP `AWS-001`/`AZR-001`) or a live control check reports a mismatch between
   requested and actual `networkExposure` (SBP `AWS-002`/`AZR-002`).

## Known failure modes

| Symptom | Likely cause | Recovery |
| :--- | :--- | :--- |
| `conftest` denies with `SBP AWS-003`/`AZR-002` | Requested `networkExposure` doesn't match the planned `map_public_ip_on_launch` / NSG `AllowInternetOutbound` rule | Re-check the request's `requirements.access.networkExposure` value; this should not occur unless the Terraform was hand-edited outside the pipeline |
| `conftest` denies with `SBP AWS-005`/`AZR-005` | `networkAclProfile: restrictive` was requested but no dedicated NACL/NSG resource is in the plan | Re-run `terraform plan` after confirming no local override skips the restrictive resource block |
| `terraform apply` fails with an overlapping-CIDR or out-of-range error | Requested `cidrBlock` overlaps an existing subnet in the parent VPC/VNet, or falls outside its address space | Resubmit with a non-overlapping CIDR that is a subset of the parent network's address space |
| Pipeline rejects at authorization stage citing missing change reference | `context.environment: prd` request had no `context.changeReference` (SBP `AWS-006`/`AZR-006`) | Resubmit with an approved change record reference |
| Post-apply verification reports the live route table/NSG doesn't match requested exposure | The `virtual-network` dependency's route tables/NSG baseline changed after this subnet was created | Escalate to the `virtual-network` capability owner; re-run `read` to confirm current state before deciding on remediation |

## Recovery procedures

- **create**: re-submit the same request (same `requestId`) — the pipeline's concurrency group
  serializes reruns, and Terraform's plan will show no changes if the subnet already exists
  exactly as requested.
- **read**: no recovery needed; re-run to get current state.
- **upgrade**: re-submit with corrected `requirements.<category>` values; Terraform updates the
  existing subnet's exposure/ACL posture in place where the provider supports in-place update
  (note: changing `cidrBlock` on an existing subnet is not supported by either provider and
  requires `delete` + `create`).
- **delete**: re-submit the same delete request; if the subnet was already removed, Terraform's
  plan will show no changes and the pipeline reports `completed`.
- **partially completed**: check the evidence artifact's per-control verification results
  (`evidence.evidenceLocation`) to identify which post-apply control check failed, then re-run the
  same operation once the underlying condition is resolved.
