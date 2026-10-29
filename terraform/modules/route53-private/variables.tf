variable "zone_name" {
  description = "Private hosted zone name (e.g. 'cl.cp.east1.example.internal')"
  type        = string
}

variable "comment" {
  description = "Zone comment"
  type        = string
  default     = "cp-benchmark-kit private zone"
}

variable "local_vpc_id" {
  description = "VPC ID in the same region as this zone"
  type        = string
}

variable "local_vpc_region" {
  description = "Region of the local VPC"
  type        = string
}

variable "peer_vpc_id" {
  description = "VPC ID in the OTHER region (for cross-region cluster-link resolution). Leave empty to skip."
  type        = string
  default     = ""
}

variable "peer_vpc_region" {
  description = "Region of the peer VPC. Required if peer_vpc_id is set."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}
