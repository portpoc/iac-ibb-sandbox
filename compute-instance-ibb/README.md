# Compute Instance IBB

A technology-agnostic **Compute Instance** capability, delivered as an Infrastructure Building
Block: Technical Reference Design + Security Blueprint + Infrastructure-as-Code + Deployment Pipeline,
bound together by [`ibb-manifest.yaml`](./ibb-manifest.yaml).

- **Owner:** cloud-foundations
- **Support:** cloud-foundations@dsv.com
- **Status:** draft — not yet released; see [`CHANGELOG.md`](./CHANGELOG.md)

## What this capability is

Creates and manages a single virtual compute instance inside an existing subnet — with a defined
sizing tier, exposure (public/private), disk encryption posture, and instance-level firewall
posture — without a consumer needing to know or choose which cloud provider's compute primitives
sit underneath.

## Supported implementations

| Platform | Reference Design | Security Blueprint |
| :--- | :--- | :--- |
| aws | [reference-designs/aws/reference-design.md](./reference-designs/aws/reference-design.md) | [security-blueprints/aws/security-blueprint.md](./security-blueprints/aws/security-blueprint.md) |

## Supported operations

- `validate` — dry-run the request against the schema, version/implementation pin, and
  authorization checks without provisioning anything.
- `create` — create a new instance.
- `read` — read the current state of an instance.
- `upgrade` — update an existing instance's sizing, exposure, or security posture in place.
- `delete` — delete an instance.

## Consuming this IBB

Consumers call the pipeline in [`pipelines/`](./pipelines/) with the mandatory context envelope
(see `05-standards-contracts.md` §8 in the architecture repo) and the agnostic requirement
parameters defined in
[`schemas/compute-instance-input-v1.schema.json`](./schemas/compute-instance-input-v1.schema.json).
See [`examples/`](./examples/) for a minimal runnable request.

Consumers pin an explicit `buildingBlock.version` — floating references (`latest`, a branch, `main`)
are prohibited (`VER-004`).

## Requirements

`requirements` is nested by category — `requirements.<category>.<property>` — grouped under the
fixed, cross-IBB categories defined in
[`requirement-dictionary/requirement-properties.yaml`](../requirement-dictionary/requirement-properties.yaml).

### sizing

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `computeTier` | `small`, `medium`, `large`, `xlarge` | Abstract vCPU/RAM sizing tier; maps internally to a specific instance type. |

### access

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `networkExposure` | `private`, `public` | Whether the instance is assigned a public IP (`public`) or stays internal-only (`private`). |

### resilience

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `availabilityZoneIndex` | integer ≥ 0 | Ordinal zone placement within the region; must resolve to the same zone as the target subnet. |
| `terminationProtection` | boolean | Whether the instance is protected against accidental termination. |

### security

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `encryptionRequired` | boolean | Whether the root volume must use a customer-managed key vs. the platform default. The root volume is always encrypted either way. |
| `securityGroupProfile` | `default`, `restrictive` | Baseline instance-level security group posture. |

### operations

| Property | Values | Meaning |
| :--- | :--- | :--- |
| `subnetId` | string | Identifier of the subnet this instance is launched into, resolved via the `subnet` dependency. |
| `osFamily` | `linux`, `windows` | Operating system family; drives platform-approved base image selection internally. |

## Dependencies

- `subnet` — the subnet this instance is launched into must already exist.
- `identity` — supplies the IAM instance profile/role this capability attaches, and the pipeline's
  scoped execution role.
- `key-management` — supplies the customer-managed key used when `encryptionRequired: true`.

## Contributing

Write access is gated by [`CODEOWNERS`](./CODEOWNERS). Trunk-based, small PRs, conventional commits.
See [`docs/runbook.md`](./docs/runbook.md) for support and escalation.
