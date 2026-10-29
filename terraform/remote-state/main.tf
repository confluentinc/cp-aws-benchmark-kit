# ============================================================================
# Remote state bootstrap — one-time per AWS account.
#
# Creates:
#   - S3 bucket for Terraform state (versioned, SSE-encrypted)
#   - DynamoDB table for state locking
#
# Run FIRST (before any envs/* apply), then copy the bucket + table names into
# envs/east1/backend.tf and envs/east2/backend.tf.
#
# Usage:
#   cd terraform/remote-state
#   terraform init
#   terraform apply
#   terraform output   # grab the bucket name + table name
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  # Local state ONLY for this bootstrap (chicken-and-egg).
}

variable "aws_profile" {
  type = string
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "bucket_name" {
  description = "S3 bucket name for Terraform state (globally unique). Suggested: cp-benchmark-kit-tfstate-<account-id>"
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "cp-benchmark-kit-tfstate-lock"
}

provider "aws" {
  region  = var.region
  profile = var.aws_profile
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_lock" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "bucket_name" {
  value       = aws_s3_bucket.tfstate.id
  description = "Paste into envs/east1/backend.tf and envs/east2/backend.tf as `bucket = \"...\"`"
}

output "table_name" {
  value       = aws_dynamodb_table.tfstate_lock.id
  description = "Paste into envs/*/backend.tf as `dynamodb_table = \"...\"`"
}
