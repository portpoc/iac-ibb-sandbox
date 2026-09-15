# DNS Record — AWS Technical Reference Design

- **Capability:** dns-record
- **Platform:** aws
- **Owning IBB:** dns-record@0.1.0
- **TRD version:** 0.1.0
- **Status:** draft
- **Owner:** platform-networking

## 1. Identity

Capability, platform, owning IBB and version, TRD version, status, owner (as above).

## 2. Selected technology

| Concern | Decision |
| :--- | :--- |
| DNS service | Amazon Route 53, existing public hosted zone (zone creation is out of scope — this capability manages records inside a zone that already exists and is on the approved allow-list, SBP `AWS-002`) |
| Record lookup | `data.aws_route53_zone` by domain name, not by hardcoded zone ID, so the same Terraform works across accounts |
| Record types | `A`, `CNAME`, `TXT` only — the smallest set that covers the vast majority of application record needs without exposing zone-structural record types (`NS`, `SOA`, apex delegation) |
| Naming convention | Record FQDN is always `<recordName>.<dnsZone>` (both required; no bare-apex record support in v0.1.0) |
| Access model | IAM role scoped to `route53:ChangeResourceRecordSets` / `route53:GetHostedZone` / `route53:ListResourceRecordSets` on the allow-listed hosted zone ARNs only, assumed via OIDC from the pipeline (SBP `AWS-001`) |
| Data protection | Route 53 records are globally public DNS data — no record content encryption exists or is meaningful; instead, `context.dataClassification: confidential` requests are rejected pre-apply (SBP `AWS-003`) |
| Availability | Route 53 is a managed, multi-AZ, globally-replicated authoritative DNS service; no availability configuration is exposed to the consumer |

## 3. Architecture and components

```
Consumer request (input schema)
        │
        ▼
Pipeline (github-actions | jenkins)
  ├─ schema + version/platform pin check
  ├─ policy-as-code gate (policies/aws/aws-dns-record.rego)
  ├─ requirementMapping → terraform variables
  └─ terraform apply/destroy
        │
        ▼
data.aws_route53_zone (lookup by dnsZone)
        │
        ▼
aws_route53_record (recordName.dnsZone, recordType, ttlSeconds, recordValues)
        │
        ▼
Route 53 authoritative DNS + query logging → logging capability (dependency)
```

## 4. Network topology

No network placement — Route 53 is a public, global, unauthenticated-query DNS service. The only
"network" concern this capability manages is which hosted zones may be targeted at all (an
allow-list, SBP `AWS-002`), not connectivity to the resource itself.

## 5. Configuration model

Every consumer-facing knob is exposed via `requirements.operations` and mapped 1:1 through
`ibb-manifest.yaml`'s `requirementMapping.aws.operations` into the identically-named Terraform
variables in `iac/aws/variables.tf`. There is no AWS-specific setting exposed beyond the agnostic
contract — no routing policy, health-check, or alias-target configuration in v0.1.0.

## 6. Availability and resilience

Route 53 itself provides the availability guarantee (AWS-managed, no consumer-configurable
replication). This capability does not expose an `availabilityClass` requirement — there is nothing
for the consumer to choose.

## 7. Backup and recovery

Record state is fully described by the Terraform configuration and remote state; recovery is
re-`apply` from the last-known-good request/state, not a data backup/restore process. Terraform
state itself is protected per the standard remote-backend configuration in `iac/aws/versions.tf`.

## 8. Observability integration

- Route 53 hosted zone query logging (where enabled on the zone) is forwarded through the
  `logging` capability dependency.
- Every `ChangeResourceRecordSets` API call is captured via the account's CloudTrail trail
  (global service events), which is a prerequisite this capability depends on, not something it
  provisions itself (SBP `AWS-004`).

## 9. Required integrations

- `logging` (declared in `ibb-manifest.yaml` `dependencies`) — receives Route 53 query logs and
  CloudTrail events for this capability's changes.
- The pipeline's OIDC identity provider / IAM role trust relationship (platform-provisioned,
  consumed not managed by this IBB).

## 10. Platform-specific constraints

- Route 53 `TTL` is ignored for alias records (not used here — this capability only creates
  standard, non-alias record sets).
- A hosted zone must already exist and be on the platform allow-list; this capability cannot
  create or delete hosted zones.
- Rate limits on `ChangeResourceRecordSets` (5 requests/sec per account) apply; high-volume
  consumers should batch via a single request rather than many rapid individual calls.

## 11. Consumption interface

A consumer submits a request matching `schemas/dns-record-input-v1.schema.json` to the pipeline.
On `create`/`upgrade`, the pipeline returns `result.recordId` (the Route 53 record set identifier,
`<zoneId>_<name>_<type>`) and `result.fqdn` (the record's fully-qualified name) once `status` is
`completed`. On `read`, the same `result` shape reflects live state. On `delete`, `result` is empty
and `status: completed` confirms removal.

## 12. Operational responsibilities

| Responsibility | This IBB (platform-networking) | Consuming solution |
| :--- | :--- | :--- |
| Hosted zone existence and allow-listing | Owns and maintains | Requests inclusion |
| Record lifecycle (create/read/upgrade/delete) | Executes via pipeline | Initiates via request |
| DNS resolution correctness after change propagation | Verifies post-apply (SBP verification) | Confirms in their own health checks |
| CloudTrail / query logging pipeline | Owns (via `logging` dependency) | Consumes for their own audit needs |

## 13. Traceability

- Paired Security Blueprint: `security-blueprints/aws/security-blueprint.md@0.1.0`
- IaC implementation: `iac/aws@0.1.0`
- Pipeline logic: `pipelines/github-actions/dns-record.yml@0.1.0`, `pipelines/jenkins/Jenkinsfile@0.1.0`
