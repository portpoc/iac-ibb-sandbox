variable "application_id" {
  type        = string
  description = "context.applicationId — the consuming application's identifier."
}

variable "environment" {
  type        = string
  description = "context.environment."
  validation {
    condition     = contains(["dev", "qua", "tst", "ppr", "prd"], var.environment)
    error_message = "environment must be one of dev, qua, tst, ppr, prd."
  }
}

variable "data_classification" {
  type        = string
  description = "context.dataClassification. Recorded as a tag only — subnets carry no data, so no value is rejected."
  validation {
    condition     = contains(["internal", "confidential"], var.data_classification)
    error_message = "data_classification must be internal or confidential."
  }
}

variable "virtual_network_name" {
  type        = string
  description = "requirements.operations.parentNetworkId — the Azure VNet name this subnet is created within, resolved via the virtual-network capability."
}

variable "resource_group_name" {
  type        = string
  description = "The resource group of the parent VNet, resolved by the pipeline alongside virtual_network_name from the virtual-network capability's output — not a separate consumer-facing input."
}

variable "address_prefix" {
  type        = string
  description = "requirements.sizing.cidrBlock — must be a subset of the parent VNet's address space and not overlap an existing subnet."
}

variable "network_exposure" {
  type        = string
  description = "requirements.access.networkExposure."
  validation {
    condition     = contains(["private", "public"], var.network_exposure)
    error_message = "network_exposure must be private or public."
  }
}

variable "availability_zone_index" {
  type        = number
  description = "requirements.resilience.availabilityZoneIndex — carried through as a tag only; azure subnets are zone-agnostic."
  validation {
    condition     = var.availability_zone_index >= 0
    error_message = "availability_zone_index must be >= 0."
  }
}

variable "network_acl_profile" {
  type        = string
  description = "requirements.security.networkAclProfile."
  validation {
    condition     = contains(["default", "restrictive"], var.network_acl_profile)
    error_message = "network_acl_profile must be default or restrictive."
  }
}
