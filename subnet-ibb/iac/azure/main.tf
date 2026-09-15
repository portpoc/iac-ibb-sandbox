locals {
  common_tags = {
    "ibb:name"            = "subnet"
    "ibb:version"         = "0.1.0"
    "app:id"              = var.application_id
    "app:environment"     = var.environment
    "data:classification" = var.data_classification
    "az:index"            = tostring(var.availability_zone_index)
  }

  subnet_name = "${var.application_id}-${var.environment}-snet"
}

# SBP AZR-006: parentNetworkId must resolve to a VNet that already exists, provisioned by the
# virtual-network capability dependency — this IBB never creates or modifies the VNet itself.
data "azurerm_virtual_network" "this" {
  name                = var.virtual_network_name
  resource_group_name = var.resource_group_name
}

# SBP AZR-001: all changes to this subnet happen only under the pipeline's scoped, RBAC-limited
# Azure AD identity (enforced outside Terraform, at role-assignment level — see
# security-blueprints/azure/security-blueprint.md AZR-001).
resource "azurerm_subnet" "this" {
  name                 = local.subnet_name
  resource_group_name  = var.resource_group_name
  virtual_network_name = data.azurerm_virtual_network.this.name
  address_prefixes     = [var.address_prefix]
}

# SBP AZR-002/AZR-005: the NSG's default rule set mirrors the requested exposure and ACL profile —
# a restrictive profile scopes allowed traffic to the parent VNet's own address space only;
# a default profile falls back to the platform baseline (allow VNet-internal, deny internet inbound).
resource "azurerm_network_security_group" "this" {
  name                = "${local.subnet_name}-nsg"
  location            = data.azurerm_virtual_network.this.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  security_rule {
    name                       = "AllowVnetInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = var.network_acl_profile == "restrictive" ? data.azurerm_virtual_network.this.address_space[0] : "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = var.network_exposure == "public" ? "Allow" : "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  subnet_id                 = azurerm_subnet.this.id
  network_security_group_id = azurerm_network_security_group.this.id
}

# SBP AZR-002/AZR-003: the route table's default route mirrors the requested exposure — public
# subnets route 0.0.0.0/0 to the Internet next hop; private subnets carry no such route (traffic
# falls back to the VNet's own approved egress path, owned by the virtual-network dependency).
resource "azurerm_route_table" "this" {
  name                = "${local.subnet_name}-rt"
  location            = data.azurerm_virtual_network.this.location
  resource_group_name = var.resource_group_name
  tags                = local.common_tags

  dynamic "route" {
    for_each = var.network_exposure == "public" ? [1] : []
    content {
      name           = "default-internet"
      address_prefix = "0.0.0.0/0"
      next_hop_type  = "Internet"
    }
  }
}

resource "azurerm_subnet_route_table_association" "this" {
  subnet_id      = azurerm_subnet.this.id
  route_table_id = azurerm_route_table.this.id
}
