# DNS Record — AWS Security Blueprint

- **Scope:** dns-record on aws
- **Paired Technical Reference Design:** `reference-designs/aws/reference-design.md@0.1.0`
- **Status:** draft
- **Owner:** platform-networking

## Controls

| ID | Domain | Requirement | Priority | Rationale | Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AWS-001 | Identity & Access | Pipeline assumes a scoped IAM role via OIDC federation, restricted to `route53:ChangeResourceRecordSets`, `route53:GetHostedZone`, `route53:ListResourceRecordSets` on the allow-listed hosted zone ARNs only — no static AWS credentials, no wildcard resource scope. | Critical | A broadly-scoped or static Route 53 credential could redirect traffic for any domain in the account, enabling phishing/hijacking with no time-bound revocation. | Pipeline OIDC/role-trust configuration review (not plan-time checkable) + IAM policy diff review at role-provisioning time. | Implemented |
| AWS-002 | Network Security | Only hosted zones on an explicit, pipeline-held allow-list may be targeted; the capability cannot create or operate against arbitrary/unapproved zones. | High | Without a zone allow-list, a valid but compromised request could plant records in a zone this team does not intend to expose through self-service automation. | `conftest` pre-apply against `policies/aws/aws-dns-record.rego` (`deny_zone_not_allowlisted`), checking the planned record's FQDN against the allow-list. | Implemented |
| AWS-003 | Data Protection | Requests with `context.dataClassification: confidential` are rejected outright; DNS records are globally, unauthenticated-ly public and cannot carry confidential data. | Critical | Route 53 has no concept of encryption-at-rest for record content meaningful to a DNS resolver — anything published here is world-readable by design. | `conftest` pre-apply against `policies/aws/aws-dns-record.rego` (`deny_confidential_classification`). | Implemented |
| AWS-004 | Logging & Monitoring | All `ChangeResourceRecordSets` API calls are captured by the account's CloudTrail trail (global service events), and hosted zone query logging is enabled and forwarded via the `logging` capability dependency. | High | Without change-event and query logging, a hijacked or mis-issued record change is invisible until a consumer notices resolution has broken. | Post-apply live check: `aws route53 get-query-logging-config` / CloudTrail event lookup for the executing role's `ChangeResourceRecordSets` call, recorded in pipeline evidence. | Implemented |
| AWS-005 | Compliance | Any request targeting `context.environment: prd` must carry a non-empty `context.changeReference`. | Medium | Production DNS changes affect live traffic; an approved change record gives incident responders a starting point when a record change is implicated in an outage. | Pipeline authorization stage rejects `prd` requests with no `changeReference` before any Terraform run (not plan-time checkable via Terraform, since it depends on request context, not resource attributes). | Implemented |

## Verification

Controls above are:

1. **Implemented** in `iac/aws/` — each Terraform resource annotated with the control ID
   it satisfies (`# SBP AWS-00x`), per `ART-005`.
2. **Verified pre-apply** by policy-as-code in `policies/aws/` (`SEC-004`) for `AWS-002` and
   `AWS-003`; `AWS-001`, `AWS-004`, and `AWS-005` are not plan-time checkable (they depend on
   pipeline/account configuration or request context rather than Terraform resource attributes)
   and are instead verified as described in their Verification Method column.
3. **Verified post-apply** by the pipeline re-checking live resource state, not just the Terraform
   plan — a successful `apply` is not evidence of conformance on its own (`SEC-005`).
