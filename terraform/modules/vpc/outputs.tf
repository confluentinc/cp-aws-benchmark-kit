output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "private_subnet_ids" {
  description = "List of 3 private subnet IDs (one per AZ, /22)"
  value       = aws_subnet.private[*].id
}

output "public_subnet_ids" {
  description = "List of 3 public subnet IDs (one per AZ, /22)"
  value       = aws_subnet.public[*].id
}

output "availability_zones" {
  description = "List of AZs used (us-east-1a/b/c order)"
  value       = local.azs
}
