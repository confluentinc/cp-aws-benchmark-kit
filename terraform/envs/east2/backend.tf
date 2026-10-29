# ============================================================================
# S3 remote state backend.
#
# The bucket + DynamoDB lock table are created by terraform/remote-state/.
# Run that once (per account), then populate the values below with your
# bucket name + table name, then run `terraform init` here.
#
# For a quick start WITHOUT remote state, delete this file entirely —
# Terraform will use a local .tfstate file in this directory.
# ============================================================================

terraform {
  backend "s3" {
    # Fill these in from the output of terraform/remote-state/.
    # bucket         = "cp-benchmark-kit-tfstate-123456789012"
    # key            = "east2/terraform.tfstate"
    # region         = "us-east-2"
    # dynamodb_table = "cp-benchmark-kit-tfstate-lock"
    # encrypt        = true
  }
}
