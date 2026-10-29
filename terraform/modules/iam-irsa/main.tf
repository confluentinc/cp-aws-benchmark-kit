# ============================================================================
# IAM IRSA (IAM Roles for Service Accounts) — creates roles that Kubernetes
# ServiceAccounts can assume via the EKS OIDC provider.
#
# Primary consumer: AWS Load Balancer Controller (installed via Helm in
# bootstrap/01-core-addons.sh). AWS LB Controller needs permissions to
# create/manage NLBs + target groups.
#
# EBS CSI driver IRSA is handled inside the eks-cluster module since it's
# an EKS-managed addon with its own lifecycle.
# ============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  oidc_provider_url = replace(var.oidc_issuer_url, "https://", "")
}

# ============================================================================
# AWS Load Balancer Controller
# ============================================================================

resource "aws_iam_role" "aws_lb_controller" {
  name = "${var.cluster_name}-aws-lb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"
      Principal = {
        Federated = var.oidc_provider_arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_provider_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_provider_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = var.tags
}

# Policy — pulled from upstream AWS LB Controller GitHub release artifact.
# Documented at: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/installation/
# The full policy is ~250 lines of JSON. We inline a condensed version here
# that covers NLB creation/management + target group ops. For production use,
# curl the official policy from the AWS LB Controller release:
#   https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
# and save it as policies/aws-lb-controller.json alongside this file.
resource "aws_iam_policy" "aws_lb_controller" {
  name   = "${var.cluster_name}-aws-lb-controller"
  policy = file("${path.module}/policies/aws-lb-controller.json")
  tags   = var.tags
}

resource "aws_iam_role_policy_attachment" "aws_lb_controller" {
  policy_arn = aws_iam_policy.aws_lb_controller.arn
  role       = aws_iam_role.aws_lb_controller.name
}
