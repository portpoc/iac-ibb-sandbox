# DNS Record IBB — Operational Runbook

- **Owner:** platform-networking
- **Support:** #platform-networking

## Support

Request help in **#platform-networking** (Slack). For production-impacting DNS issues, page the
platform-networking on-call via the standard PagerDuty escalation for that channel.

## Escalation

1. #platform-networking Slack channel — first line of support, business hours.
2. platform-networking on-call (PagerDuty) — for `prd` DNS outages or suspected hijack/mis-issuance.
3. Security team — if a change appears to have been made outside the pipeline's scoped IAM role
   (see SBP `AWS-001`) or targets a zone not on the allow-list (SBP `AWS-002`).

## Known failure modes

| Symptom | Likely cause | Recovery |
| :--- | :--- | :--- |
| `conftest` denies with `SBP AWS-002` | Requested `dnsZone`/`recordName` FQDN doesn't match any entry in `allowed_zone_suffixes` (`policies/aws/aws-dns-record.rego`) | Confirm the zone is genuinely intended for self-service automation, then add it via a CODEOWNERS-reviewed PR to the rego allow-list |
| `conftest` denies with `SBP AWS-003` | `context.dataClassification` was submitted as `confidential` | This capability cannot be used for confidential data — DNS is public by design. Use `internal` or route the requirement elsewhere |
| Pipeline rejects at authorization stage citing missing change reference | `context.environment: prd` request had no `context.changeReference` (SBP `AWS-005`) | Resubmit with an approved change record reference |
| `terraform apply` fails with a Route 53 rate-limit error | More than 5 `ChangeResourceRecordSets` calls/sec against the account | Retry after a short backoff; batch multiple record changes into fewer requests where possible |
| Post-apply verification reports DNS not yet resolving the new value | Normal TTL-bound propagation delay, or a resolver caching the previous value | Wait out the previous record's `ttlSeconds`; re-run the `read` operation to confirm authoritative state independent of caching |

## Recovery procedures

- **create**: re-submit the same request (same `requestId`) — the pipeline's concurrency group
  serializes reruns, and Terraform's plan will show no changes if the record already exists exactly
  as requested.
- **read**: no recovery needed; re-run to get current state.
- **upgrade**: re-submit with corrected `requirements.operations` values; Terraform updates the
  existing record in place.
- **delete**: re-submit the same delete request; if the record was already removed, Terraform's
  plan will show no changes and the pipeline reports `completed`.
- **partially completed**: check the evidence artifact's per-control verification results
  (`evidence.evidenceLocation`) to identify which post-apply control check failed, then re-run the
  same operation once the underlying condition is resolved.
