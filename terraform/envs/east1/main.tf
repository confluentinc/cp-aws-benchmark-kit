# ============================================================================
# cp-benchmark-kit — Region 1 (default: us-east-1) root module.
#
# Calls the shared modules to provision:
#   - VPC + subnets
#   - EKS cluster + OIDC + core addons
#   - 4 nodegroups: ng-base, ng-brokers, ng-controllers, ng-omb-clients
#     (ng-ingress-xl is created separately in client-path/topology-b-nginx-ingress/
#      via eksctl, since it's optional and depends on topology choice.)
#   - Route53 private hosted zone
#   - IAM IRSA role for AWS LB Controller
#
# Reads terraform.tfvars (user-created from terraform.tfvars.example).
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

provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "cp-benchmark-kit"
      Environment = "east1"
      ManagedBy   = "terraform"
    }
  }
}

# ─── VPC ───
module "vpc" {
  source = "../../modules/vpc"

  name_prefix           = var.cluster_name
  vpc_cidr              = var.vpc_cidr
  cluster_name_for_tags = var.cluster_name
  tags = {
    Region = var.region
  }
}

# ─── EKS cluster ───
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  cluster_name        = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  public_subnet_ids   = module.vpc.public_subnet_ids
  public_access_cidrs = var.cluster_public_access_cidrs
}

# ─── Nodegroups ───
# Base nodegroup — holds system pods, Prometheus/Grafana, utility workloads.
module "ng_base" {
  source = "../../modules/eks-nodegroup"

  cluster_name   = module.eks_cluster.cluster_name
  nodegroup_name = "ng-base"
  create_role    = true
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = "t3.medium"
  ami_type       = "AL2023_x86_64_STANDARD"
  min_size       = 1
  max_size       = 4
  desired_size   = 2
  labels = {
    "cflt-cp-nodeType" = "base"
  }
}

# Broker nodegroup — 15 brokers, one per node, Graviton3, large memory.
module "ng_brokers" {
  source = "../../modules/eks-nodegroup"

  cluster_name   = module.eks_cluster.cluster_name
  nodegroup_name = "ng-brokers"
  create_role    = false
  node_role_arn  = module.ng_base.node_role_arn
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = var.broker_instance
  ami_type       = "AL2023_ARM_64_STANDARD"
  min_size       = var.broker_count
  max_size       = var.broker_count
  desired_size   = var.broker_count
  disk_size_gb   = 100       # root disk; broker data is on EBS PVs via EBS CSI driver
  labels = {
    "cflt-cp-nodeType" = "broker"
  }
}

# OMB client nodegroup — 10 benchmark clients, large NIC.
module "ng_omb_clients" {
  source = "../../modules/eks-nodegroup"

  cluster_name   = module.eks_cluster.cluster_name
  nodegroup_name = "ng-omb-clients"
  create_role    = false
  node_role_arn  = module.ng_base.node_role_arn
  subnet_ids     = module.vpc.private_subnet_ids
  instance_type  = var.omb_worker_instance
  ami_type       = "AL2023_ARM_64_STANDARD"
  min_size       = var.omb_worker_count
  max_size       = var.omb_worker_count
  desired_size   = var.omb_worker_count
  labels = {
    "cflt-cp-nodeType" = "omb-client"
  }
  taints = [{
    key    = "dedicated"
    value  = "omb-client"
    effect = "NO_SCHEDULE"
  }]
}

# ─── Route53 private hosted zone ───
module "route53" {
  source = "../../modules/route53-private"

  zone_name        = var.route53_zone_name
  local_vpc_id     = module.vpc.vpc_id
  local_vpc_region = var.region
  # peer_vpc_id and peer_vpc_region left empty — set after east2 is created
  # by running: terraform apply with -var 'peer_vpc_id=...' or editing tfvars.
}

# ─── IAM IRSA ───
module "iam_irsa" {
  source = "../../modules/iam-irsa"

  cluster_name       = module.eks_cluster.cluster_name
  oidc_issuer_url    = module.eks_cluster.cluster_oidc_issuer_url
  oidc_provider_arn  = module.eks_cluster.cluster_oidc_provider_arn
}
