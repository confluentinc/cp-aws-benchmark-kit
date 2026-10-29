variable "cluster_name" {
  description = "EKS cluster name (used in role naming)"
  type        = string
}

variable "oidc_issuer_url" {
  description = "EKS OIDC issuer URL (from eks-cluster module output)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN (from eks-cluster module output)"
  type        = string
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
