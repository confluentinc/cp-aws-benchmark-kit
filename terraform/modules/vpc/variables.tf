variable "name_prefix" {
  description = "Prefix for all resource names (e.g. 'cp-east1')"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (/16 recommended for /22 subnet math)"
  type        = string
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && tonumber(split("/", var.vpc_cidr)[1]) <= 16
    error_message = "vpc_cidr must be a valid CIDR with prefix /16 or shorter."
  }
}

variable "cluster_name_for_tags" {
  description = "EKS cluster name — used in subnet tags for cluster-autoscaler / AWS LB Controller discovery"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default     = {}
}
