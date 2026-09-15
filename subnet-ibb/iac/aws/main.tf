locals {
  common_tags = {
    "ibb:name"            = "subnet"
    "ibb:version"         = "0.1.0"
    "app:id"              = var.application_id
    "app:environment"     = var.environment
    "data:classification" = var.data_classification
  }

  route_table_tier = var.network_exposure == "public" ? "public" : "private"
}

# SBP AWS-006: parentNetworkId (vpc_id) must resolve to a VPC that already exists, provisioned by
# the virtual-network capability dependency — this IBB never creates or modifies the VPC itself.
data "aws_vpc" "this" {
  id = var.vpc_id
}

# SBP AWS-002 (support): zone placement is resolved ordinally so the same availabilityZoneIndex
# value stays portable across regions.
data "aws_availability_zones" "available" {
  state = "available"
}

# SBP AWS-002/AWS-003: the route table this subnet associates with is selected by the Tier tag the
# virtual-network capability is expected to have applied to its public/private route tables — this
# capability only selects between them, it never creates VPC-level route tables.
data "aws_route_table" "selected" {
  vpc_id = data.aws_vpc.this.id
  filter {
    name   = "tag:Tier"
    values = [local.route_table_tier]
  }
}

# SBP AWS-001: all changes to this subnet happen only under the pipeline's scoped IAM role, limited
# to this resource type and this capability's tagged resources (enforced outside Terraform, at role
# and policy level — see security-blueprints/aws/security-blueprint.md AWS-001).
# SBP AWS-003: map_public_ip_on_launch mirrors network_exposure exactly, in depth alongside the
# route table association below.
resource "aws_subnet" "this" {
  vpc_id                  = data.aws_vpc.this.id
  cidr_block              = var.cidr_block
  availability_zone       = data.aws_availability_zones.available.names[var.availability_zone_index]
  map_public_ip_on_launch = var.network_exposure == "public"

  tags = merge(local.common_tags, {
    "Name" = "${var.application_id}-${var.environment}-${var.availability_zone_index}"
  })
}

# SBP AWS-002: associates this subnet with the route table matching its requested exposure.
resource "aws_route_table_association" "this" {
  subnet_id      = aws_subnet.this.id
  route_table_id = data.aws_route_table.selected.id
}

# SBP AWS-005: a dedicated, restrictive NACL is created only when explicitly requested; otherwise
# the subnet remains on the VPC's default NACL (no resource created).
resource "aws_network_acl" "restrictive" {
  count  = var.network_acl_profile == "restrictive" ? 1 : 0
  vpc_id = data.aws_vpc.this.id

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = data.aws_vpc.this.cidr_block
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = merge(local.common_tags, {
    "Name" = "${var.application_id}-${var.environment}-restrictive-nacl"
  })
}

resource "aws_network_acl_association" "restrictive" {
  count          = var.network_acl_profile == "restrictive" ? 1 : 0
  subnet_id      = aws_subnet.this.id
  network_acl_id = aws_network_acl.restrictive[0].id
}
