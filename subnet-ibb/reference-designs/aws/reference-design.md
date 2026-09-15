# Subnet — AWS Technical Reference Design

- **Capability:** subnet
- **Platform:** aws
- **Owning IBB:** subnet@0.1.0
- **TRD version:** 0.1.0
- **Status:** draft
- **Owner:** cloud-foundations

## 1. Identity

Capability, platform, owning IBB and version, TRD version, status, owner (as above).

## 2. Selected technology

| Concern | Decision |
| :--- | :--- |
| Network segment | `aws_subnet`, created inside an existing VPC (VPC creation is out of scope — `parentNetworkId` resolves via the `virtual-network` capability's output, SBP `AWS-006`) |
| Zone placement | `data.aws_availability_zones` (state = `available`) indexed by `availabilityZoneIndex`, so the ordinal request value stays portable across regions |
| Exposure model | `networkExposure: public` associates the subnet's route table with a default route to the VPC's Internet Gateway and sets `map_public_ip_on_launch = true`; `private` associates a route table with no default internet route and `map_public_ip_on_launch = false` (SBP `AWS-002`, `AWS-003`) |
| Route table lookup | `data.aws_route_table`, filtered by the parent VPC id and a `Tier` tag (`public`/`private`) that the `virtual-network` capability is expected to have already applied to its route tables — this capability does not create VPC-level route tables itself |
| ACL posture | `networkAclProfile: restrictive` creates a dedicated `aws_network_acl` scoped to the subnet, allowing only the parent VPC's own CIDR plus ephemeral return traffic, denying everything else; `default` leaves the subnet on the VPC's default NACL (SBP `AWS-005`) |
| Naming convention | Subnet `Name` tag is `<applicationId>-<environment>-<availabilityZoneIndex>` |
| Access model | Pipeline assumes a scoped IAM role via OIDC federation, limited to `ec2:CreateSubnet`/`DeleteSubnet`/`ModifySubnetAttribute`/`Describe*`/`CreateNetworkAcl*` on this capability's tagged resources only (SBP `AWS-001`) |
| Data protection | Subnets carry no data of their own; `context.dataClassification` is recorded as a tag for evidence only, not enforced as a resource attribute |
| Availability | A single subnet occupies exactly one Availability Zone by AWS design; multi-AZ redundancy is achieved by the consumer requesting multiple subnets (one per `availabilityZoneIndex`), not by this capability internally |

## 3. Architecture and components

```
Consumer request (input schema)
        │
        ▼
Pipeline (github-actions)
  ├─ schema + version/platform pin check
  ├─ policy-as-code gate (policies/aws/aws-subnet.rego)
  ├─ requirementMapping → terraform variables
  └─ terraform apply/destroy
        │
        ▼
data.aws_availability_zones (indexed by availabilityZoneIndex)
        │
        ▼
aws_subnet (vpc_id, cidr_block, availability_zone, map_public_ip_on_launch)
        │
        ├─ aws_route_table_association → data.aws_route_table (Tier=public|private)
        └─ aws_network_acl (only when networkAclProfile = restrictive) → aws_network_acl_association
```

## 4. Network topology

The subnet is placed inside the VPC identified by `parentNetworkId`. Its exposure is entirely a
function of which route table it is associated with — this capability never creates or modifies
an Internet Gateway or NAT Gateway itself (those are `virtual-network` responsibilities); it only
selects between the VPC's already-provisioned public and private route tables (SBP `AWS-002`).

## 5. Configuration model

Every consumer-facing knob is exposed via `requirements.<category>` and mapped through
`ibb-manifest.yaml`'s `requirementMapping.aws` into the identically-purposed Terraform variables in
`iac/aws/variables.tf`. No AWS-specific setting is exposed beyond the agnostic contract — no
custom route entries, no NACL rule authoring, no VPC peering in v0.1.0.

## 6. Availability and resilience

A subnet is bound to exactly one Availability Zone. This capability does not expose a
consumer-facing "availability class" — resilience across zones is achieved by provisioning
multiple subnet resources (one request per zone), each independently created and independently
destroyable.

## 7. Backup and recovery

Subnet state is fully described by the Terraform configuration and remote state; recovery is
re-`apply` from the last-known-good request/state, not a data backup/restore process (a subnet
holds no data). Terraform state itself is protected per the standard remote-backend configuration
in `iac/aws/versions.tf`.

## 8. Observability integration

- VPC Flow Logs on the parent VPC (provisioned by the `virtual-network` dependency, not this
  capability) capture traffic to/from this subnet's ENIs.
- Every `CreateSubnet`/`DeleteSubnet`/`ModifySubnetAttribute` API call is captured via the
  account's CloudTrail trail, forwarded through the `logging` capability where present (SBP
  `AWS-004`).

## 9. Required integrations

- `virtual-network` (declared in `ibb-manifest.yaml` `dependencies`) — supplies `parentNetworkId`
  (the VPC id) and the pre-existing public/private route tables this capability associates with.
- `identity` (declared in `dependencies`) — provisions the pipeline's OIDC-federated IAM role.

## 10. Platform-specific constraints

- A subnet cannot span multiple Availability Zones; `availabilityZoneIndex` selects exactly one.
- `cidrBlock` must be a subset of the parent VPC's CIDR block and must not overlap any existing
  subnet in that VPC — Terraform surfaces this as an `apply`-time AWS API error, not a plan-time
  policy check, since it depends on live VPC state.
- The five AWS-reserved addresses per subnet (network, broadcast, and the first four host
  addresses) are not usable by workloads; this is AWS platform behaviour, not a setting.

## 11. Consumption interface

A consumer submits a request matching `schemas/subnet-input-v1.schema.json` to the pipeline.
On `create`/`upgrade`, the pipeline returns `result.subnetId` (the AWS subnet id, `subnet-xxxx`),
`result.cidrBlock` (the actual allocated block), `result.availabilityZone` (the resolved zone name,
e.g. `us-east-1a`), and `result.routeTableId` once `status` is `completed`. On `read`, the same
`result` shape reflects live state. On `delete`, `result` is empty and `status: completed`
confirms removal.

## 12. Operational responsibilities

| Responsibility | This IBB (cloud-foundations) | Consuming solution |
| :--- | :--- | :--- |
| VPC existence, Internet/NAT Gateway, base route tables | Consumed via `virtual-network` (not owned here) | Requests the subnet within an already-provisioned VPC |
| Subnet lifecycle (create/read/upgrade/delete) | Executes via pipeline | Initiates via request |
| CIDR/AZ allocation correctness | Verifies post-apply (SBP verification) | Confirms in their own workload placement |
| Flow logs / CloudTrail pipeline | Owns (via `logging`/`virtual-network` dependencies) | Consumes for their own audit needs |

## 13. Traceability

- Paired Security Blueprint: `security-blueprints/aws/security-blueprint.md@0.1.0`
- IaC implementation: `iac/aws@0.1.0`
- Pipeline logic: `pipelines/github-actions/subnet.yml@0.1.0`
