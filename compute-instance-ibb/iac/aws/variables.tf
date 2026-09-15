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
  description = "context.dataClassification. Recorded as a tag only; enforcement is via networkExposure/encryptionRequired, not a rejected value here."
  validation {
    condition     = contains(["internal", "confidential"], var.data_classification)
    error_message = "data_classification must be internal or confidential."
  }
}

variable "subnet_id" {
  type        = string
  description = "requirements.operations.subnetId — the AWS subnet id this instance is launched into, resolved via the subnet capability."
}

variable "instance_profile_name" {
  type        = string
  description = "Externally-provisioned IAM instance profile name, resolved via the identity capability dependency. This Terraform never creates IAM roles/policies."
}

variable "kms_key_arn" {
  type        = string
  description = "Externally-provisioned customer-managed KMS key ARN, resolved via the key-management capability dependency. Used only when encryption_required is true."
  default     = null
}

variable "compute_tier" {
  type        = string
  description = "requirements.sizing.computeTier."
  validation {
    condition     = contains(["small", "medium", "large", "xlarge"], var.compute_tier)
    error_message = "compute_tier must be one of small, medium, large, xlarge."
  }
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
  description = "requirements.resilience.availabilityZoneIndex — ordinal index into the region's available AZs. Must resolve to the same zone as the target subnet."
  validation {
    condition     = var.availability_zone_index >= 0
    error_message = "availability_zone_index must be >= 0."
  }
}

variable "termination_protection" {
  type        = bool
  description = "requirements.resilience.terminationProtection."
}

variable "encryption_required" {
  type        = bool
  description = "requirements.security.encryptionRequired — whether the root volume must use the key-management customer-managed key vs. the AWS-managed default key. The root volume is always encrypted either way."
}

variable "security_group_profile" {
  type        = string
  description = "requirements.security.securityGroupProfile."
  validation {
    condition     = contains(["default", "restrictive"], var.security_group_profile)
    error_message = "security_group_profile must be default or restrictive."
  }
}

variable "os_family" {
  type        = string
  description = "requirements.operations.osFamily — drives AMI resolution via SSM parameter lookup."
  validation {
    condition     = contains(["linux", "windows"], var.os_family)
    error_message = "os_family must be linux or windows."
  }
}
