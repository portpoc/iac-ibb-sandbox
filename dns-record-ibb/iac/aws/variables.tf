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
  description = "context.dataClassification. 'confidential' is rejected pre-apply by policy (SBP AWS-003), never reaches apply."
  validation {
    condition     = contains(["internal", "confidential"], var.data_classification)
    error_message = "data_classification must be internal or confidential."
  }
}

variable "dns_zone" {
  type        = string
  description = "requirements.operations.dnsZone — the hosted zone's domain name, e.g. example.com."
}

variable "record_name" {
  type        = string
  description = "requirements.operations.recordName — record name relative to dns_zone."
}

variable "record_type" {
  type        = string
  description = "requirements.operations.recordType."
  validation {
    condition     = contains(["A", "CNAME", "TXT"], var.record_type)
    error_message = "record_type must be one of A, CNAME, TXT."
  }
}

variable "ttl_seconds" {
  type        = number
  description = "requirements.operations.ttlSeconds."
  validation {
    condition     = var.ttl_seconds >= 1
    error_message = "ttl_seconds must be >= 1."
  }
}

variable "record_values" {
  type        = list(string)
  description = "requirements.operations.recordValues."
  validation {
    condition     = length(var.record_values) >= 1
    error_message = "record_values must contain at least one value."
  }
}
