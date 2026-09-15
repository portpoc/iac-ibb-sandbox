# DNS Record IBB

A technology-agnostic **DNS Record** capability, delivered as an Infrastructure Building
Block: Technical Reference Design + Security Blueprint + Infrastructure-as-Code + Deployment Pipeline,
bound together by [`ibb-manifest.yaml`](./ibb-manifest.yaml).

- **Owner:** platform-networking
- **Support:** #platform-networking
- **Status:** draft — not yet released; see [`CHANGELOG.md`](./CHANGELOG.md)

## What this capability is

Manages a single DNS resource record inside an existing, pre-approved DNS zone — create, read,
update, or delete a record's type, TTL, and target values — without a consumer needing to know or
choose which DNS provider or hosted-zone mechanism sits underneath.

## Supported implementations

| Platform | Reference Design | Security Blueprint |
| :--- | :--- | :--- |
| aws | [reference-designs/aws/reference-design.md](./reference-designs/aws/reference-design.md) | [security-blueprints/aws/security-blueprint.md](./security-blueprints/aws/security-blueprint.md) |

## Supported operations

- `validate` — dry-run the request against the schema, hosted-zone allow-list, and classification
  policy without provisioning anything.
- `create` — create a new DNS record.
- `read` — read the current state of a record.
- `upgrade` — update an existing record's type, TTL, or values in place.
- `delete` — delete a record.

## Consuming this IBB

Consumers call the pipeline in [`pipelines/`](./pipelines/) with the mandatory context envelope
(see `05-standards-contracts.md` §8 in the architecture repo) and the agnostic requirement
parameters defined in [`schemas/dns-record-input-v1.schema.json`](./schemas/dns-record-input-v1.schema.json).
See [`examples/`](./examples/) for minimal runnable requests per platform.

Consumers pin an explicit `buildingBlock.version` — floating references (`latest`, a branch, `main`)
are prohibited (`VER-004`).

## Requirements

`requirements` is nested by category — `requirements.<category>.<property>` — grouped under the
fixed, cross-IBB categories defined in
[`requirement-dictionary/requirement-properties.yaml`](../requirement-dictionary/requirement-properties.yaml).

### operations

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `dnsZone` | domain name, e.g. `example.com.` | The DNS zone the record belongs to. |
| `recordName` | string, relative to `dnsZone` | The record's name (e.g. `www`). |
| `recordType` | `A`, `CNAME`, `TXT` | DNS resource record type. |
| `ttlSeconds` | integer ≥ 1 | Cache lifetime of the record, in seconds. |
| `recordValues` | array of strings, min 1 item | Target value(s): IP address(es) for `A`, a hostname for `CNAME`, string content for `TXT`. |

## Dependencies

- `logging` — Route 53 query and API-call logs are forwarded through the logging capability
  (see SBP `AWS-004`).

## Contributing

Write access is gated by [`CODEOWNERS`](./CODEOWNERS). Trunk-based, small PRs, conventional commits.
See [`docs/runbook.md`](./docs/runbook.md) for support and escalation.
