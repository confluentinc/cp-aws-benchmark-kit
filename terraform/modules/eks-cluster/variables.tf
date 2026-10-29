variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version (e.g. '1.36')"
  type        = string
  default     = "1.36"
}

variable "vpc_id" {
  description = "VPC ID for the cluster"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs (for worker nodes + control plane ENIs)"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnet IDs (for LoadBalancer services, NAT gateways)"
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to access the EKS public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
