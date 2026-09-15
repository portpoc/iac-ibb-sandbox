locals {
  common_tags = {
    "ibb:name"            = "compute-instance"
    "ibb:version"         = "0.1.0"
    "app:id"              = var.application_id
    "app:environment"     = var.environment
    "data:classification" = var.data_classification
  }

  instance_type_map = {
    small  = "t3.small"
    medium = "t3.medium"
    large  = "t3.large"
    xlarge = "t3.xlarge"
  }

  ssm_ami_parameter_map = {
    linux   = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    windows = "/aws/service/ami-windows-latest/Windows_Server-2022-English-Full-Base"
  }
}

# SBP AWS-004 (support): subnetId must resolve to a subnet that already exists, provisioned by the
# subnet capability dependency — this IBB never creates or modifies the subnet itself.
data "aws_subnet" "this" {
  id = var.subnet_id
}

# SBP AWS-004 (support): zone placement is resolved ordinally so the same availabilityZoneIndex
# value stays portable across regions. The actual instance must land in the same zone as the
# target subnet — enforced by AWS itself at apply time, not by this data source.
data "aws_availability_zones" "available" {
  state = "available"
}

# SBP AWS-001: the launch AMI is always the latest platform-approved image for the requested
# osFamily, resolved via the public SSM parameter path — never a hardcoded AMI id.
data "aws_ssm_parameter" "ami" {
  name = local.ssm_ami_parameter_map[var.os_family]
}

# SBP AWS-005: a dedicated, restrictive security group is created only when explicitly requested;
# otherwise a baseline security group allowing only the platform's standard management ports is
# attached.
resource "aws_security_group" "this" {
  name        = "${var.application_id}-${var.environment}-${var.availability_zone_index}-sg"
  description = "Instance-level security group (${var.security_group_profile} profile) for ${var.application_id}."
  vpc_id      = data.aws_subnet.this.vpc_id

  dynamic "ingress" {
    for_each = var.security_group_profile == "restrictive" ? [1] : []
    content {
      description = "Restrictive profile: allow only from the target subnet's own CIDR."
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_blocks = [data.aws_subnet.this.cidr_block]
    }
  }

  dynamic "ingress" {
    for_each = var.security_group_profile == "default" ? [22, 3389] : []
    content {
      description = "Default profile: standard management port from the parent network's address space."
      protocol    = "tcp"
      from_port   = ingress.value
      to_port     = ingress.value
      cidr_blocks = [data.aws_subnet.this.cidr_block]
    }
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    "Name" = "${var.application_id}-${var.environment}-${var.availability_zone_index}-sg"
  })
}

# SBP AWS-001: all changes to this instance happen only under the pipeline's scoped IAM role,
# limited to this resource type and this capability's tagged resources (enforced outside
# Terraform, at role and policy level — see security-blueprints/aws/security-blueprint.md AWS-001).
# SBP AWS-002: root_block_device is always encrypted; a customer-managed key is used only when
# encryption_required is true.
# SBP AWS-003: metadata_options unconditionally enforces IMDSv2.
# SBP AWS-004: associate_public_ip_address mirrors network_exposure exactly.
# SBP AWS-006: disable_api_termination mirrors termination_protection exactly.
resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = local.instance_type_map[var.compute_tier]
  subnet_id              = var.subnet_id
  availability_zone      = data.aws_availability_zones.available.names[var.availability_zone_index]
  vpc_security_group_ids = [aws_security_group.this.id]

  associate_public_ip_address = var.network_exposure == "public"
  monitoring                  = true
  disable_api_termination     = var.termination_protection

  iam_instance_profile = var.instance_profile_name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    http_endpoint               = "enabled"
  }

  root_block_device {
    encrypted  = true
    kms_key_id = var.encryption_required ? var.kms_key_arn : null
  }

  tags = merge(local.common_tags, {
    "Name" = "${var.application_id}-${var.environment}-${var.availability_zone_index}"
  })
}
