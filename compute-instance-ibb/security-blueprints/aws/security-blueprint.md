# Compute Instance — AWS Security Blueprint

- **Scope:** compute-instance on aws
- **Paired Technical Reference Design:** `reference-designs/aws/reference-design.md@0.1.0`
- **Status:** draft
- **Owner:** cloud-foundations

## Controls

| ID | Domain | Requirement | Priority | Rationale | Verification Method | Status |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| AWS-001 | Identity & Access | Pipeline assumes a scoped IAM role via OIDC federation, restricted to `ec2:RunInstances`, `ec2:TerminateInstances`, `ec2:ModifyInstanceAttribute`, `ec2:Describe*`, `ec2:CreateSecurityGroup`, `ec2:AuthorizeSecurityGroupIngress`/`Egress`, `ec2:DeleteSecurityGroup` on this capability's tagged resources only — no static AWS credentials, no wildcard resource scope. | Critical | A broadly-scoped or static credential could launch or terminate instances anywhere in the account, or open unintended network ingress, well beyond this capability's intended blast radius. | Pipeline OIDC/role-trust configuration review (not plan-time checkable) + IAM policy diff review at role-provisioning time. | Implemented |
| AWS-002 | Data Protection | The root EBS volume is always encrypted (`encrypted = true`); when `encryptionRequired: true`, the volume additionally uses the customer-managed key supplied by the `key-management` dependency instead of the AWS-managed default key. | Critical | An unencrypted root volume exposes any data written to disk (OS logs, cached credentials, application state) to anyone with snapshot/volume access outside the instance's own access controls. | `conftest` pre-apply against `policies/aws/aws-compute-instance.rego` (`deny_unencrypted_root_volume`), checking the planned `aws_instance.root_block_device.encrypted` and, when `encryptionRequired`, `kms_key_id`. | Implemented |
| AWS-003 | Data Protection | Instance metadata service is IMDSv2-only: `metadata_options.http_tokens = "required"` and `http_put_response_hop_limit = 1`. | Critical | IMDSv1 is vulnerable to SSRF-based credential theft from the instance's attached IAM role; IMDSv2's session-token requirement closes that class of attack. | `conftest` pre-apply against `policies/aws/aws-compute-instance.rego` (`deny_imdsv1_allowed`), checking the planned `aws_instance.metadata_options`. | Implemented |
| AWS-004 | Network Security | A public IP is assigned (`associate_public_ip_address = true`) only when `networkExposure: public`; it is always `false` for `private` instances. | Critical | Auto-assigning a public IP to an instance intended to be private would make it internet-reachable regardless of the subnet's own route table, defeating the subnet-level exposure control in depth. | `conftest` pre-apply against `policies/aws/aws-compute-instance.rego` (`deny_public_ip_on_private_instance`); post-apply live check via `aws ec2 describe-instances`. | Implemented |
| AWS-005 | Network Security | An instance with `securityGroupProfile: restrictive` is attached only to a dedicated security group denying all inbound traffic except from the target subnet's own CIDR; `default` attaches the platform's baseline security group (standard management ports only, from the parent network's address space). | Medium | Without an explicit restrictive option, workloads that need instance-level network isolation beyond the subnet's NACL (e.g. regulated workloads) have no self-service path to get it. | `conftest` pre-apply against `policies/aws/aws-compute-instance.rego` (`deny_restrictive_without_dedicated_sg`), checking a dedicated `aws_security_group` resource exists when the profile is `restrictive`. | Implemented |
| AWS-006 | Platform Hardening | `disable_api_termination` mirrors the requested `terminationProtection` exactly (`true` when protection is requested, `false` otherwise). | Medium | Without this control, a `terminationProtection: true` request could be silently ignored, leaving a production instance one accidental `TerminateInstances` call away from deletion. | `conftest` pre-apply against `policies/aws/aws-compute-instance.rego` (`deny_termination_protection_mismatch`); post-apply live check via `aws ec2 describe-instance-attribute --attribute disableApiTermination`. | Implemented |
| AWS-007 | Logging & Monitoring | Detailed monitoring is enabled (`monitoring = true`), and every `RunInstances`/`TerminateInstances`/`ModifyInstanceAttribute` API call is captured by the account's CloudTrail trail. | High | Without 1-minute metrics and change-event logging, an unauthorized or mis-scoped instance change is invisible until a consumer notices degraded performance or a missing instance. | Post-apply live check: CloudTrail event lookup for the executing role's `RunInstances`/`TerminateInstances` call, recorded in pipeline evidence. | Implemented |
| AWS-008 | Compliance | Any request targeting `context.environment: prd` must carry a non-empty `context.changeReference`. | Medium | Production compute changes can affect live workloads; an approved change record gives incident responders a starting point when an instance change is implicated in an outage. | Pipeline authorization stage rejects `prd` requests with no `changeReference` before any Terraform run (not plan-time checkable via Terraform, since it depends on request context, not resource attributes). | Implemented |

## Verification

Controls above are:

1. **Implemented** in `iac/aws/` — each Terraform resource annotated with the control ID
   it satisfies (`# SBP AWS-00x`), per `ART-005`.
2. **Verified pre-apply** by policy-as-code in `policies/aws/` (`SEC-004`) for `AWS-002`,
   `AWS-003`, `AWS-004`, `AWS-005`, and `AWS-006`; `AWS-001`, `AWS-007`, and `AWS-008` are not
   plan-time checkable (they depend on pipeline/account configuration or request context rather
   than Terraform resource attributes) and are instead verified as described in their
   Verification Method column.
3. **Verified post-apply** by the pipeline re-checking live resource state, not just the Terraform
   plan — a successful `apply` is not evidence of conformance on its own (`SEC-005`).
