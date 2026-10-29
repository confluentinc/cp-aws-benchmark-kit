# ============================================================================
# Route53 private hosted zone — for internal broker + bootstrap DNS.
#
# The zone is associated with the local VPC. For bidirectional cluster-link,
# the zone from region 1 should ALSO be associated with region 2's VPC (and
# vice versa). That cross-region association is done via the vpc_association
# resource below, but requires that the OTHER region's VPC ID be passed in.
# If omitted, the zone is only associated with the local VPC.
#
# Note: cross-region R53 zone association requires the "secondary" region's
# IAM to authorize the association. This module takes care of it provided
# the TF credentials have Route53:AssociateVPCWithHostedZone perms.
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

resource "aws_route53_zone" "private" {
  name    = var.zone_name
  comment = var.comment

  vpc {
    vpc_id     = var.local_vpc_id
    vpc_region = var.local_vpc_region
  }

  tags = var.tags

  # Allow adding more VPC associations later without replacing the zone.
  lifecycle {
    ignore_changes = [vpc]
  }
}

# Optional: associate the zone with the OTHER region's VPC (for cluster-link path).
resource "aws_route53_zone_association" "peer_vpc" {
  count      = var.peer_vpc_id != "" ? 1 : 0
  zone_id    = aws_route53_zone.private.zone_id
  vpc_id     = var.peer_vpc_id
  vpc_region = var.peer_vpc_region
}
