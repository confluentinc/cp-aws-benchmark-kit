# ============================================================================
# VPC module — 3 AZs, 3 private /22 subnets + 3 public /22 subnets per AZ.
#
# /22 subnet size (1024 IPs each) is specifically chosen for NLB density:
# Topology A creates ~16 NLBs per region, each consuming a few IPs per AZ.
# /24 subnets exhaust in a 15-broker + per-broker-NLB setup.
#
# Private subnets: brokers, OMB clients, nginx-ingress, EKS control plane ENIs.
# Public subnets: NAT gateways + any internet-facing (not used by this benchmark).
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

data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
  # Split VPC CIDR into 6 /22 subnets (3 private + 3 public) for a /16 VPC.
  # /16 → /22 = 4 bits of subnet space → 16 possible /22s. We use 6.
  private_subnet_cidrs = [for i in range(3) : cidrsubnet(var.vpc_cidr, 6, i)]
  public_subnet_cidrs  = [for i in range(3) : cidrsubnet(var.vpc_cidr, 6, i + 8)]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

resource "aws_subnet" "private" {
  count                = 3
  vpc_id               = aws_vpc.main.id
  cidr_block           = local.private_subnet_cidrs[count.index]
  availability_zone    = local.azs[count.index]

  tags = merge(var.tags, {
    Name                                                 = "${var.name_prefix}-private-${local.azs[count.index]}"
    "kubernetes.io/role/internal-elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name_for_tags}" = "shared"
  })
}

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name                                                 = "${var.name_prefix}-public-${local.azs[count.index]}"
    "kubernetes.io/role/elb"                             = "1"
    "kubernetes.io/cluster/${var.cluster_name_for_tags}" = "shared"
  })
}

resource "aws_eip" "nat" {
  count  = 3
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  count         = 3
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${local.azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-public"
  })
}

resource "aws_route_table" "private" {
  count  = 3
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rt-private-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 3
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}
