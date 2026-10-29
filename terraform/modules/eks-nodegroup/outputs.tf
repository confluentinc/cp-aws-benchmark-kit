output "nodegroup_arn" {
  description = "Nodegroup ARN"
  value       = aws_eks_node_group.main.arn
}

output "nodegroup_status" {
  description = "Nodegroup status"
  value       = aws_eks_node_group.main.status
}

output "node_role_arn" {
  description = "IAM role ARN used by nodes (pass to subsequent nodegroups via create_role=false + node_role_arn)"
  value       = local.effective_node_role_arn
}

output "asg_names" {
  description = "Auto-scaling group names backing this nodegroup"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[*].name
}
