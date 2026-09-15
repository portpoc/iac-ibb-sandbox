# Compute Instance IBB — Operational Runbook

- **Owner:** cloud-foundations
- **Support:** cloud-foundations@dsv.com

## Support

Request help via **cloud-foundations@dsv.com**. For production-impacting compute issues, page the
cloud-foundations on-call via the standard escalation route for that mailbox/team.

## Escalation

1. cloud-foundations@dsv.com — first line of support, business hours.
2. cloud-foundations on-call — for `prd` instance outages or suspected exposure misconfiguration.
3. Security team — if a change appears to have been made outside the pipeline's scoped
   identity/role (see SBP `AWS-001`) or a live control check reports a mismatch between requested
   and actual `networkExposure`/encryption/IMDSv2 posture (SBP `AWS-002`/`AWS-003`/`AWS-004`).

## Known failure modes

| Symptom | Likely cause | Recovery |
| :--- | :--- | :--- |
| `conftest` denies with `SBP AWS-002` | `encryptionRequired: true` was requested but no `kms_key_id` resolved from the `key-management` dependency | Confirm the `key-management` dependency has provisioned a key and its ARN is available to the pipeline before resubmitting |
| `conftest` denies with `SBP AWS-004` | Requested `networkExposure` doesn't match the planned `associate_public_ip_address` | Re-check the request's `requirements.access.networkExposure` value; this should not occur unless the Terraform was hand-edited outside the pipeline |
| `conftest` denies with `SBP AWS-005` | `securityGroupProfile: restrictive` was requested but no dedicated security group is in the plan | Re-run `terraform plan` after confirming no local override skips the restrictive resource block |
| `terraform apply` fails with an AZ/instance-type-unavailable error | Requested `computeTier`/`availabilityZoneIndex` combination isn't offered in that zone, or the zone doesn't match the target subnet's own zone | Resubmit with a `computeTier` available in that zone, or an `availabilityZoneIndex` matching the target subnet |
| Pipeline rejects at authorization stage citing missing change reference | `context.environment: prd` request had no `context.changeReference` (SBP `AWS-008`) | Resubmit with an approved change record reference |
| Post-apply verification reports live IMDSv2/encryption/termination-protection mismatch | Instance was modified outside the pipeline's scoped role | Escalate to Security; re-run `read` to confirm current state before deciding on remediation |

## Recovery procedures

- **create**: re-submit the same request (same `requestId`) — the pipeline's concurrency group
  serializes reruns, and Terraform's plan will show no changes if the instance already exists
  exactly as requested.
- **read**: no recovery needed; re-run to get current state.
- **upgrade**: re-submit with corrected `requirements.<category>` values; Terraform updates the
  existing instance's sizing/exposure/security posture in place where the provider supports
  in-place update (note: changing `osFamily` is not supported in place by AWS and requires
  `delete` + `create`).
- **delete**: re-submit the same delete request; if the instance was already removed, Terraform's
  plan will show no changes and the pipeline reports `completed`. If `terminationProtection: true`
  is still set, the request fails until it's turned off via an `upgrade` first.
- **partially completed**: check the evidence artifact's per-control verification results
  (`evidence.evidenceLocation`) to identify which post-apply control check failed, then re-run the
  same operation once the underlying condition is resolved.
