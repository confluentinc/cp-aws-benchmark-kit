variable "cluster_name" {
  description = "EKS cluster name this nodegroup joins"
  type        = string
}

variable "nodegroup_name" {
  description = "Nodegroup name (e.g. 'ng-brokers')"
  type        = string
}

variable "create_role" {
  description = "Whether to create a new IAM node role. Set to false and pass node_role_arn when the role already exists (reuse across nodegroups)."
  type        = bool
  default     = true
}

variable "node_role_arn" {
  description = "Existing IAM node role ARN. Required when create_role=false."
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs where nodes will be placed (typically private subnets)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type (e.g. 'r7g.8xlarge', 'c7gn.8xlarge')"
  type        = string
}

variable "ami_type" {
  description = "EKS AMI family. Use AL2023_ARM_64_STANDARD for Graviton, AL2023_x86_64_STANDARD otherwise."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT"
  type        = string
  default     = "ON_DEMAND"
}

variable "disk_size_gb" {
  description = "EBS gp3 root volume size per node"
  type        = number
  default     = 100
}

variable "min_size" {
  description = "Min nodes in ASG"
  type        = number
}

variable "max_size" {
  description = "Max nodes in ASG"
  type        = number
}

variable "desired_size" {
  description = "Desired node count"
  type        = number
}

variable "labels" {
  description = "Kubernetes node labels (e.g. {cflt-cp-nodeType = 'broker'})"
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes node taints"
  type = list(object({
    key    = string
    value  = string
    effect = string # NO_SCHEDULE, PREFER_NO_SCHEDULE, NO_EXECUTE
  }))
  default = []
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
