# Subnet IBB

A technology-agnostic **Subnet** capability, delivered as an Infrastructure Building
Block: Technical Reference Design + Security Blueprint + Infrastructure-as-Code + Deployment Pipeline,
bound together by [`ibb-manifest.yaml`](./ibb-manifest.yaml).

- **Owner:** cloud-foundations
- **Support:** cloud-foundations@dsv.com
- **Status:** draft — not yet released; see [`CHANGELOG.md`](./CHANGELOG.md)

## What this capability is

Creates and manages a single network subnet inside an existing parent virtual network — a
segment of address space with a defined exposure (public/private) and access-control posture —
without a consumer needing to know or choose which cloud provider's networking primitives sit
underneath.

## Supported implementations

| Platform | Reference Design | Security Blueprint |
| :--- | :--- | :--- |
| aws | [reference-designs/aws/reference-design.md](./reference-designs/aws/reference-design.md) | [security-blueprints/aws/security-blueprint.md](./security-blueprints/aws/security-blueprint.md) |
| azure | [reference-designs/azure/reference-design.md](./reference-designs/azure/reference-design.md) | [security-blueprints/azure/security-blueprint.md](./security-blueprints/azure/security-blueprint.md) |

## Supported operations

- `validate` — dry-run the request against the schema, version/implementation pin, and
  authorization checks without provisioning anything.
- `create` — create a new subnet.
- `read` — read the current state of a subnet.
- `upgrade` — update an existing subnet's exposure or ACL posture in place.
- `delete` — delete a subnet.

## Consuming this IBB

Consumers call the pipeline in [`pipelines/`](./pipelines/) with the mandatory context envelope
(see `05-standards-contracts.md` §8 in the architecture repo) and the agnostic requirement
parameters defined in [`schemas/subnet-input-v1.schema.json`](./schemas/subnet-input-v1.schema.json).
See [`examples/`](./examples/) for minimal runnable requests per platform.

Consumers pin an explicit `buildingBlock.version` — floating references (`latest`, a branch, `main`)
are prohibited (`VER-004`).

## Requirements

`requirements` is nested by category — `requirements.<category>.<property>` — grouped under the
fixed, cross-IBB categories defined in
[`requirement-dictionary/requirement-properties.yaml`](../requirement-dictionary/requirement-properties.yaml).

### sizing

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `cidrBlock` | CIDR notation, e.g. `10.0.1.0/24` | Address space allocated to this subnet within the parent network. |

### access

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `networkExposure` | `private`, `public` | Whether the subnet routes egress via a public gateway (`public`) or stays internal-only (`private`). |

### resilience

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `availabilityZoneIndex` | integer ≥ 0 | Ordinal zone placement within the region; mapped internally per platform to the actual zone id. |

### security

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `networkAclProfile` | `default`, `restrictive` | Baseline NACL/NSG posture applied to the subnet. |

### operations

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `parentNetworkId` | string | Identifier of the parent VPC/VNet this subnet is created within, resolved via the `virtual-network` dependency. |

## Dependencies

- `virtual-network` — the parent VPC/VNet this subnet is created within must already exist.
- `identity` — the pipeline's scoped execution role/identity is provisioned by this dependency.

## Contributing

Write access is gated by [`CODEOWNERS`](./CODEOWNERS). Trunk-based, small PRs, conventional commits.
See [`docs/runbook.md`](./docs/runbook.md) for support and escalation.
