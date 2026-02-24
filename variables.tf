variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "aws-client-vpn"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "client_vpn_cidr" {
  description = "CIDR block for VPN client IP addresses"
  type        = string
  default     = "172.16.0.0/22"
}

variable "endpoint_count" {
  description = "Number of test endpoints to create"
  type        = number
  default     = 50
}
