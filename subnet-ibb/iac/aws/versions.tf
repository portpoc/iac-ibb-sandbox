terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend — org-specific values not known to this scaffold. Fill in the real
  # bucket/table/key before first apply; see scaffold-ibb SKILL.md §6.
  backend "s3" {
    # bucket         = "REPLACE_WITH_ORG_TFSTATE_BUCKET"
    # key            = "subnet-ibb/aws/terraform.tfstate"
    # region         = "REPLACE_WITH_ORG_TFSTATE_REGION"
    # dynamodb_table = "REPLACE_WITH_ORG_TFSTATE_LOCK_TABLE"
    # encrypt        = true
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "AWS region for the provider and the parent VPC/subnet."
  default     = "us-east-1"
}
