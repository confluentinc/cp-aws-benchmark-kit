# tgw-peering (optional)

Cross-region Transit Gateway peering for cluster-link traffic between east1 and east2 VPCs.

**Most enterprise sites already have cross-region connectivity managed by the platform networking team.** This module is a stub — fill it in only if you're deploying to a greenfield account that needs TGW from scratch.

## What you'd put here

- `aws_ec2_transit_gateway` (one per region)
- `aws_ec2_transit_gateway_vpc_attachment` (attach each VPC to its region's TGW)
- `aws_ec2_transit_gateway_peering_attachment` (peer east1 TGW to east2 TGW)
- `aws_ec2_transit_gateway_peering_attachment_accepter` (accept the peering in east2)
- Routes in both VPC private route tables pointing at the TGW for the OTHER region's CIDR

## Alternative: VPC peering

For single-digit cluster-link latency, VPC peering is simpler and cheaper than TGW. Use `aws_vpc_peering_connection` + routes directly, no TGW needed.

## Minimum requirement for cluster-link to work

Brokers in east1 must reach brokers in east2's CLUSTERLINK NLB IPs on port 9098. Any mechanism that provides that connectivity works (TGW, VPC peering, PrivateLink, direct VPN). The cp-benchmark-kit setup doesn't care which.
