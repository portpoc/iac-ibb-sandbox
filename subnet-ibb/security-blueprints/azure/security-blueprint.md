# Subnet — Azure Security Blueprint

- **Scope:** subnet on azure
- **Paired Technical Reference Design:** `reference-designs/azure/reference-design.md@0.1.0`
- **Status:** draft
- **Owner:** cloud-foundations

## Controls

| ID | Domain | Requirement | Priority | Rationale | Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AZR-001 | Identity & Access | Pipeline assumes a scoped Azure AD identity via OIDC federation, holding a custom RBAC role limited to `Microsoft.Network/virtualNetworks/subnets/*`, `Microsoft.Network/networkSecurityGroups/*`, `Microsoft.Network/routeTables/*` on the target resource group only — no long-lived service principal client secret, no subscription-wide role assignment. | Critical | A broadly-scoped or static credential could create or delete network segments across any VNet in the subscription, enabling lateral-movement paths or accidental outages far beyond this capability's intended blast radius. | Pipeline OIDC/federated-credential configuration review (not plan-time checkable) + RBAC role assignment diff review at role-provisioning time. | Implemented |
| AZR-002 | Network Security | A subnet with `networkExposure: public` is associated only with an NSG allowing internet-bound traffic and a route table with a default route to an internet-facing next hop; a `private` subnet is associated only with an NSG denying internet-bound traffic by default. | Critical | Associating a private-intent subnet with a permissive NSG by mistake would silently expose workloads placed in it to the internet with no application-level warning. | `conftest` pre-apply against `policies/azure/azure-subnet.rego` (`deny_exposure_nsg_mismatch`), checking the planned NSG's default rules against the requested `networkExposure`. | Implemented |
| AZR-003 | Network Security | A `private` subnet's associated route table must not contain a default route (`0.0.0.0/0`) pointing at the Internet next-hop type. | High | A stray internet-bound default route on a subnet intended to be private would bypass NSG controls for any traffic relying on default routing, defeating the exposure control above in depth. | `conftest` pre-apply against `policies/azure/azure-subnet.rego` (`deny_private_subnet_internet_route`). | Implemented |
| AZR-004 | Logging & Monitoring | Every subnet/NSG/route-table create, modify, or delete operation is captured in Azure Activity Log, and NSG Flow Logs are enabled on the subnet's network security group, forwarded through the `logging` capability. | High | Without change-event and flow logging, an unauthorized or mis-scoped subnet change is invisible until a consumer notices connectivity has broken. | Post-apply live check: Activity Log query for the executing identity's write operations against the subnet/NSG, recorded in pipeline evidence. | Implemented |
| AZR-005 | Network Security | A subnet with `networkAclProfile: restrictive` is associated with a dedicated NSG allowing only the parent VNet's own address space and denying all else by default; `default` associates the platform's baseline NSG. | Medium | Without an explicit restrictive option, workloads that need network-layer isolation beyond application-level controls (e.g. regulated workloads) have no self-service path to get it. | `conftest` pre-apply against `policies/azure/azure-subnet.rego` (`deny_restrictive_without_dedicated_nsg`), checking a dedicated `azurerm_network_security_group` resource exists when the profile is `restrictive`. | Implemented |
| AZR-006 | Compliance | Any request targeting `context.environment: prd` must carry a non-empty `context.changeReference`. | Medium | Production network topology changes can affect live traffic paths; an approved change record gives incident responders a starting point when a subnet change is implicated in an outage. | Pipeline authorization stage rejects `prd` requests with no `changeReference` before any Terraform run (not plan-time checkable via Terraform, since it depends on request context, not resource attributes). | Implemented |

## Verification

Controls above are:

1. **Implemented** in `iac/azure/` — each Terraform resource annotated with the control ID
   it satisfies (`# SBP AZR-00x`), per `ART-005`.
2. **Verified pre-apply** by policy-as-code in `policies/azure/` (`SEC-004`) for `AZR-002`,
   `AZR-003`, and `AZR-005`; `AZR-001`, `AZR-004`, and `AZR-006` are not plan-time checkable (they
   depend on pipeline/subscription configuration or request context rather than Terraform resource
   attributes) and are instead verified as described in their Verification Method column.
3. **Verified post-apply** by the pipeline re-checking live resource state, not just the Terraform
   plan — a successful `apply` is not evidence of conformance on its own (`SEC-005`).
