# Compute Instance — AWS Technical Reference Design

- **Capability:** compute-instance
- **Platform:** aws
- **Owning IBB:** compute-instance@0.1.0
- **TRD version:** 0.1.0
- **Status:** draft
- **Owner:** cloud-foundations

## 1. Identity

Capability, platform, owning IBB and version, TRD version, status, owner (as above).

## 2. Selected technology

| Concern | Decision |
| :--- | :--- |
| Compute resource | `aws_instance`, launched into an existing subnet (subnet creation is out of scope — `subnetId` resolves via the `subnet` capability's output, SBP `AWS-004`) |
| Sizing | `computeTier` maps internally to a fixed EC2 instance type (`small`→`t3.small`, `medium`→`t3.medium`, `large`→`t3.large`, `xlarge`→`t3.xlarge`); the literal instance type never appears in the agnostic contract |
| Image selection | `osFamily` resolves the launch AMI via `data.aws_ssm_parameter` against the platform-approved public SSM parameter path (Amazon Linux 2023 for `linux`, Windows Server 2022 for `windows`) — never a hardcoded AMI id, so the latest patched image is always used (SBP `AWS-001`) |
| Zone placement | `data.aws_availability_zones` (state = `available`) indexed by `availabilityZoneIndex`; must resolve to the same zone the target subnet already occupies — verified post-apply against live subnet state, not at plan time |
| Exposure model | `networkExposure: public` sets `associate_public_ip_address = true`; `private` sets it `false`. Actual internet reachability still depends on the target subnet's own route table, owned by the `subnet` capability (SBP `AWS-004`) |
| Identity | `aws_iam_instance_profile` referencing an externally-provisioned IAM role (ARN supplied by the `identity` dependency) — this Terraform never creates IAM roles or policies itself |
| Disk encryption | Root EBS volume is always `encrypted = true`; `encryptionRequired: true` additionally sets `kms_key_id` to the customer-managed key ARN supplied by the `key-management` dependency (SBP `AWS-002`) |
| Metadata service | `metadata_options` enforces IMDSv2 only (`http_tokens = "required"`, `http_put_response_hop_limit = 1`) unconditionally — not a consumer-facing knob (SBP `AWS-003`) |
| Network posture | `securityGroupProfile: restrictive` creates a dedicated `aws_security_group` denying all inbound except from the target subnet's own CIDR; `default` attaches a baseline security group allowing only the platform's standard management ports from the parent network's address space (SBP `AWS-005`) |
| Termination protection | `terminationProtection` maps 1:1 to `disable_api_termination` (SBP `AWS-006`) |
| Naming convention | Instance `Name` tag is `<applicationId>-<environment>-<availabilityZoneIndex>` |
| Data protection | `context.dataClassification` is recorded as a tag for evidence; enforcement of confidentiality is via `networkExposure` and `encryptionRequired`, not a separate resource attribute |

## 3. Architecture and components

```
Consumer request (input schema)
        │
        ▼
Pipeline (github-actions)
  ├─ schema + version/platform pin check
  ├─ policy-as-code gate (policies/aws/aws-compute-instance.rego)
  ├─ requirementMapping → terraform variables
  └─ terraform apply/destroy
        │
        ▼
data.aws_availability_zones (indexed by availabilityZoneIndex)
data.aws_subnet (subnetId, from the subnet dependency)
data.aws_ssm_parameter (osFamily → latest approved AMI)
        │
        ▼
aws_security_group (default | restrictive, per securityGroupProfile)
        │
        ▼
aws_instance (ami, instance_type, subnet_id, associate_public_ip_address,
              metadata_options, root_block_device, disable_api_termination,
              iam_instance_profile)
```

## 4. Network topology

The instance is placed inside the subnet identified by `subnetId`. Its exposure is a function of
`associate_public_ip_address` plus the target subnet's own route table (owned by `subnet`) — this
capability never creates or modifies a subnet, route table, or Internet/NAT Gateway itself. The
attached security group is the only network control this capability owns directly (SBP `AWS-004`,
`AWS-005`).

## 5. Configuration model

Every consumer-facing knob is exposed via `requirements.<category>` and mapped through
`ibb-manifest.yaml`'s `requirementMapping.aws` into the identically-purposed Terraform variables in
`iac/aws/variables.tf`. No AWS-specific setting is exposed beyond the agnostic contract — no
custom user-data scripts, no EBS volume authoring beyond the root volume, no placement groups in
v0.1.0.

## 6. Availability and resilience

An instance is bound to exactly one Availability Zone. This capability does not expose a
consumer-facing "availability class" — resilience across zones is achieved by the consuming
solution provisioning multiple instances (one request per zone) or by a higher-level capability
(e.g. an auto-scaling-group IBB, out of scope for v0.1.0) built on top of this one.

## 7. Backup and recovery

Instance state (beyond the root volume's contents) is fully described by the Terraform
configuration and remote state; recovery is re-`apply` from the last-known-good request/state.
Root volume data backup/restore (snapshots) is out of scope for v0.1.0 and is a consuming
solution's own responsibility. Terraform state itself is protected per the standard remote-backend
configuration in `iac/aws/versions.tf`.

## 8. Observability integration

- Detailed monitoring (`monitoring = true`) publishes 1-minute CloudWatch metrics for every
  instance (SBP `AWS-007`).
- Every `RunInstances`/`TerminateInstances`/`ModifyInstanceAttribute` API call is captured via the
  account's CloudTrail trail, forwarded through the `logging` capability where present.

## 9. Required integrations

- `subnet` (declared in `ibb-manifest.yaml` `dependencies`) — supplies `subnetId` and the
  pre-existing route table this capability's reachability depends on.
- `identity` (declared in `dependencies`) — supplies the IAM instance profile/role ARN this
  capability attaches, and provisions the pipeline's OIDC-federated execution role.
- `key-management` (declared in `dependencies`) — supplies the customer-managed KMS key ARN used
  when `encryptionRequired: true`.

## 10. Platform-specific constraints

- An instance cannot span multiple Availability Zones; `availabilityZoneIndex` must resolve to the
  same zone the target `subnetId` already occupies — Terraform surfaces a mismatch as an
  `apply`-time AWS API error, not a plan-time policy check, since it depends on live subnet state.
- Instance type availability varies by Availability Zone; an unsupported `computeTier`/zone
  combination surfaces as an `apply`-time AWS API error.
- Changing `computeTier` (instance type) or `subnetId` on an existing instance requires a stop/
  start cycle that Terraform manages automatically via `aws_instance`'s update-in-place behavior;
  changing `osFamily` requires `delete` + `create` since it changes the AMI the instance was
  launched from.

## 11. Consumption interface

A consumer submits a request matching `schemas/compute-instance-input-v1.schema.json` to the
pipeline. On `create`/`upgrade`, the pipeline returns `result.instanceId` (the AWS instance id,
`i-xxxx`), `result.privateIp`, `result.publicIp` (`null` when `networkExposure: private`), and
`result.availabilityZone` (the resolved zone name, e.g. `us-east-1a`) once `status` is
`completed`. On `read`, the same `result` shape reflects live state. On `delete`, `result` is
empty and `status: completed` confirms removal.

## 12. Operational responsibilities

| Responsibility | This IBB (cloud-foundations) | Consuming solution |
| :--- | :--- | :--- |
| Subnet existence, route tables | Consumed via `subnet` (not owned here) | Requests the instance within an already-provisioned subnet |
| IAM role/instance profile provisioning | Consumed via `identity` (not owned here) | Requests the instance with the identity dependency already satisfied |
| Instance lifecycle (create/read/upgrade/delete) | Executes via pipeline | Initiates via request |
| Root volume encryption key lifecycle | Consumed via `key-management` (not owned here) | Confirms key policy grants this capability's execution role encrypt/decrypt access |
| CloudTrail / CloudWatch pipeline | Owns (via `logging` dependency where present) | Consumes for their own audit needs |

## 13. Traceability

- Paired Security Blueprint: `security-blueprints/aws/security-blueprint.md@0.1.0`
- IaC implementation: `iac/aws@0.1.0`
- Pipeline logic: `pipelines/github-actions/compute-instance.yml@0.1.0`
