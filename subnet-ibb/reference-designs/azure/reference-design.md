# Subnet — Azure Technical Reference Design

- **Capability:** subnet
- **Platform:** azure
- **Owning IBB:** subnet@0.1.0
- **TRD version:** 0.1.0
- **Status:** draft
- **Owner:** cloud-foundations

## 1. Identity

Capability, platform, owning IBB and version, TRD version, status, owner (as above).

## 2. Selected technology

| Concern | Decision |
| :--- | :--- |
| Network segment | `azurerm_subnet`, created inside an existing Virtual Network (VNet creation is out of scope — `parentNetworkId` resolves to the VNet name via the `virtual-network` capability's output, SBP `AZR-006`) |
| Zone placement | Azure subnets themselves are zone-agnostic (zones apply to resources placed inside, not the subnet resource); `availabilityZoneIndex` is carried through as a tag for downstream zone-aware placement, not a subnet Terraform attribute |
| Exposure model | `networkExposure: public` associates the subnet with an `azurerm_network_security_group` allowing internet-bound egress/ingress and an `azurerm_route_table` with a default route to an internet-facing next hop; `private` associates an NSG that denies internet-bound traffic by default and forces egress through the parent network's approved path (e.g. a firewall/NAT gateway, provisioned by `virtual-network`) (SBP `AZR-002`, `AZR-003`) |
| ACL posture | `networkAclProfile: restrictive` creates a dedicated NSG with an explicit deny-by-default rule set scoped to the parent VNet's own address space, replacing the platform baseline NSG; `default` associates the platform's baseline NSG (SBP `AZR-005`) |
| Naming convention | Subnet name is `<applicationId>-<environment>-snet` |
| Access model | Pipeline assumes a scoped Azure AD identity via OIDC federation, holding a custom RBAC role limited to `Microsoft.Network/virtualNetworks/subnets/*`, `Microsoft.Network/networkSecurityGroups/*`, `Microsoft.Network/routeTables/*` on the target resource group only — no long-lived service principal secret (SBP `AZR-001`) |
| Data protection | Subnets carry no data of their own; `context.dataClassification` is recorded as a tag for evidence only, not enforced as a resource attribute |
| Availability | Azure Virtual Network and its subnets are regional constructs with no consumer-configurable replication; zone-level availability is a property of the resources placed inside the subnet, not the subnet itself |

## 3. Architecture and components

```
Consumer request (input schema)
        │
        ▼
Pipeline (github-actions)
  ├─ schema + version/platform pin check
  ├─ policy-as-code gate (policies/azure/azure-subnet.rego)
  ├─ requirementMapping → terraform variables
  └─ terraform apply/destroy
        │
        ▼
data.azurerm_virtual_network (looked up by parentNetworkId + resource group)
        │
        ▼
azurerm_subnet (address_prefixes, virtual_network_name)
        │
        ├─ azurerm_network_security_group (+ association) — exposure/ACL posture
        └─ azurerm_route_table (+ association) — default route per networkExposure
```

## 4. Network topology

The subnet is placed inside the Virtual Network identified by `parentNetworkId`, within the same
resource group as that VNet. Its exposure is a function of the NSG and route table associated with
it — this capability never creates or modifies the VNet's peering, VPN Gateway, or Azure Firewall
itself (those are `virtual-network` responsibilities); it only attaches its own NSG/route table to
the subnet it creates (SBP `AZR-002`).

## 5. Configuration model

Every consumer-facing knob is exposed via `requirements.<category>` and mapped through
`ibb-manifest.yaml`'s `requirementMapping.azure` into the identically-purposed Terraform variables
in `iac/azure/variables.tf`. No Azure-specific setting is exposed beyond the agnostic contract — no
custom NSG rule authoring, no service endpoints/delegations in v0.1.0.

## 6. Availability and resilience

Azure subnets are regional, not zonal, resources. This capability does not expose a
consumer-facing "availability class" for the subnet itself — zone-level resilience is a property
of the compute/data resources a consumer later places inside the subnet.

## 7. Backup and recovery

Subnet state is fully described by the Terraform configuration and remote state; recovery is
re-`apply` from the last-known-good request/state, not a data backup/restore process (a subnet
holds no data). Terraform state itself is protected per the standard remote-backend configuration
in `iac/azure/versions.tf`.

## 8. Observability integration

- NSG Flow Logs on the subnet's network security group capture traffic to/from resources placed
  in this subnet, forwarded through the `logging` capability where present.
- Every subnet/NSG/route-table write operation is captured via Azure Activity Log (SBP `AZR-004`).

## 9. Required integrations

- `virtual-network` (declared in `ibb-manifest.yaml` `dependencies`) — supplies `parentNetworkId`
  (the VNet name and its resource group) and the approved egress path for private subnets.
- `identity` (declared in `dependencies`) — provisions the pipeline's OIDC-federated Azure AD
  identity and RBAC role assignment.

## 10. Platform-specific constraints

- `cidrBlock` must be a subset of the parent VNet's address space and must not overlap any
  existing subnet in that VNet — Terraform surfaces this as an `apply`-time Azure API error, not a
  plan-time policy check, since it depends on live VNet state.
- Azure reserves the first four and the last address in every subnet for platform use; this is
  Azure platform behaviour, not a setting.
- Certain Azure PaaS services require subnet delegation (`azurerm_subnet_delegation`); this is out
  of scope for v0.1.0 and not exposed as a requirement.

## 11. Consumption interface

A consumer submits a request matching `schemas/subnet-input-v1.schema.json` to the pipeline.
On `create`/`upgrade`, the pipeline returns `result.subnetId` (the Azure subnet resource id),
`result.cidrBlock` (the actual allocated prefix), and `result.routeTableId` once `status` is
`completed`. `result.availabilityZone` is omitted for azure — subnets are zone-agnostic. On
`read`, the same `result` shape reflects live state. On `delete`, `result` is empty and
`status: completed` confirms removal.

## 12. Operational responsibilities

| Responsibility | This IBB (cloud-foundations) | Consuming solution |
| :--- | :--- | :--- |
| VNet existence, peering, firewall/NAT egress path | Consumed via `virtual-network` (not owned here) | Requests the subnet within an already-provisioned VNet |
| Subnet lifecycle (create/read/upgrade/delete) | Executes via pipeline | Initiates via request |
| CIDR allocation correctness | Verifies post-apply (SBP verification) | Confirms in their own workload placement |
| Flow logs / Activity Log pipeline | Owns (via `logging`/`virtual-network` dependencies) | Consumes for their own audit needs |

## 13. Traceability

- Paired Security Blueprint: `security-blueprints/azure/security-blueprint.md@0.1.0`
- IaC implementation: `iac/azure@0.1.0`
- Pipeline logic: `pipelines/github-actions/subnet.yml@0.1.0`
