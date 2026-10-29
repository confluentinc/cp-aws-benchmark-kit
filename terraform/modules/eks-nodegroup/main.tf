# ============================================================================
# EKS managed nodegroup — reusable module for ng-base / ng-brokers /
# ng-omb-clients / ng-ingress-xl.
#
# Each invocation creates one nodegroup with its own instance type, size,
# subnets, labels, and taints. The role is shared across nodegroups per cluster
# (created here on first invocation; attach `create_role = false` on subsequent
# invocations and pass `node_role_arn` instead).
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

data "aws_partition" "current" {}

# ─── Node IAM role (shared across all nodegroups per cluster) ───
resource "aws_iam_role" "node" {
  count = var.create_role ? 1 : 0
  name  = "${var.cluster_name}-${var.nodegroup_name}-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_amazon_eks_worker_node_policy" {
  count      = var.create_role ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_amazon_eks_cni_policy" {
  count      = var.create_role ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node[0].name
}

resource "aws_iam_role_policy_attachment" "node_amazon_ec2_container_registry_read_only" {
  count      = var.create_role ? 1 : 0
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node[0].name
}

locals {
  effective_node_role_arn = var.create_role ? aws_iam_role.node[0].arn : var.node_role_arn
}

# ─── Nodegroup ───
resource "aws_eks_node_group" "main" {
  cluster_name    = var.cluster_name
  node_group_name = var.nodegroup_name
  node_role_arn   = local.effective_node_role_arn
  subnet_ids      = var.subnet_ids
  ami_type        = var.ami_type           # AL2023_ARM_64_STANDARD for Graviton; AL2023_x86_64_STANDARD otherwise
  instance_types  = [var.instance_type]
  capacity_type   = var.capacity_type      # ON_DEMAND or SPOT
  disk_size       = var.disk_size_gb

  scaling_config {
    min_size     = var.min_size
    max_size     = var.max_size
    desired_size = var.desired_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.nodegroup_name}"
  })

  # Ensure IAM role policies are attached before the nodegroup tries to use them.
  depends_on = [
    aws_iam_role_policy_attachment.node_amazon_eks_worker_node_policy,
    aws_iam_role_policy_attachment.node_amazon_eks_cni_policy,
    aws_iam_role_policy_attachment.node_amazon_ec2_container_registry_read_only,
  ]
}
