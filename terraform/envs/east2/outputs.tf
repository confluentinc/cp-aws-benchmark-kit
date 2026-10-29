output "cluster_name" {
  value = module.eks_cluster.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_cluster.cluster_endpoint
}

output "cluster_oidc_issuer_url" {
  value = module.eks_cluster.cluster_oidc_issuer_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "3 private subnet IDs — paste these into .env PRIVATE_SUBNETS_REGION2 (comma-separated)"
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  value = module.vpc.public_subnet_ids
}

output "nginx_ingress_subnet_ids" {
  description = "Same as private_subnet_ids for this setup — paste into .env NGINX_INGRESS_SUBNETS_REGION2"
  value       = module.vpc.private_subnet_ids
}

output "route53_zone_id" {
  description = "Paste into .env ROUTE53_ZONE_ID_REGION2"
  value       = module.route53.zone_id
}

output "route53_zone_name" {
  value = module.route53.zone_name
}

output "aws_lb_controller_role_arn" {
  description = "Pass to Helm install of aws-load-balancer-controller as serviceAccount.annotations.eks.amazonaws.com/role-arn"
  value       = module.iam_irsa.aws_lb_controller_role_arn
}

output "availability_zones" {
  value = module.vpc.availability_zones
}
