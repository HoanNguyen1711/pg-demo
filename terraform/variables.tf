variable "region" {
  description = "Singapore is the closest region to Vietnam (lowest latency for a live demo). Must be allowed by the org SCP's RegionFloor."
  type        = string
  default     = "ap-southeast-1"
}

variable "owner" {
  type    = string
  default = "hoan"
}

variable "identifier" {
  type    = string
  default = "pg-demo"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "instance_class" {
  description = "db.t4g.large = 2 vCPU, 8 GiB RAM. Enough to keep the 10M-row demo data warm in cache."
  type        = string
  default     = "db.t4g.large"
}

variable "bastion_instance_type" {
  description = "Only forwards TCP for one psql session; the smallest Graviton size is plenty."
  type        = string
  default     = "t4g.nano"
}

variable "engine_version" {
  description = "Major version only: RDS picks the latest 16.x minor."
  type        = string
  default     = "16"
}

variable "allocated_storage_gb" {
  description = "Data + indexes after all demos are about 2.5 GB; 20 GB gp3 leaves room for WAL and bloat demos."
  type        = number
  default     = 20
}

variable "local_port" {
  description = "Port on the laptop for the SSM tunnel. Not 5432, so it doesn't clash with the docker-compose backup."
  type        = number
  default     = 15432
}
