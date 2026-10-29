output "aws_lb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller ServiceAccount"
  value       = aws_iam_role.aws_lb_controller.arn
}
