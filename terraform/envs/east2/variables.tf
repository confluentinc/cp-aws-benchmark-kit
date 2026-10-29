variable "aws_profile" {
  description = "AWS CLI profile"
  type        = string
}

variable "region" {
  description = "AWS region (default us-east-2)"
  type        = string
  default     = "us-east-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.36"
}

variable "vpc_cidr" {
  description = "VPC CIDR (must be /16 or shorter)"
  type        = string
}

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to access the EKS public API endpoint. Narrow this for production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "broker_count" {
  description = "Number of Kafka brokers"
  type        = number
  default     = 15
}

variable "broker_instance" {
  description = "EC2 instance type for brokers"
  type        = string
  default     = "r7g.8xlarge"
}

variable "omb_worker_count" {
  description = "Number of OMB benchmark client nodes"
  type        = number
  default     = 10
}

variable "omb_worker_instance" {
  description = "EC2 instance type for OMB clients"
  type        = string
  default     = "c7gn.8xlarge"
}

variable "route53_zone_name" {
  description = "Private hosted zone name (e.g. 'cl.cp.east2.example.internal')"
  type        = string
}
