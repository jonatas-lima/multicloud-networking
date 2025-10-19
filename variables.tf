variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-2"
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.aws_vpc_cidr, 0, 0))
    error_message = "Invalid CIDR block for AWS VPC network."
  }
}

variable "aws_vpc_name" {
  description = "Name of the AWS VPC."
  type        = string
  default     = "multi-cloud-vpc"
}

variable "aws_asn" {
  description = "Amazon Side ASN for the AWS VPN Gateway."
  type        = string
  default     = "64512"
}

variable "aws_ssh_keypair_name" {
  description = "Name of the AWS SSH key pair."
  type        = string
}

variable "aws_ssh_public_key_path" {
  description = "Path to the AWS SSH public key. Used to login to EC2 instances."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "aws_ssh_keypair_exists" {
  description = "Set to true if the AWS SSH key pair already exists."
  type        = bool
  default     = false
}

variable "aws_ami" {
  description = "AMI ID for the AWS EC2 instances."
  type        = string
  default     = "ami-0199d4b5b8b4fde0e"
}

variable "aws_instance_type" {
  description = "Instance type for the AWS EC2 instances."
  type        = string
  default     = "t3a.micro"
}

variable "gcp_project_id" {
  description = "GCP Project ID."
  type        = string
  default     = "multi-region-network"
}

variable "gcp_region" {
  description = "GCP region for the resources."
  type        = string
  default     = "us-west1"
}

variable "gcp_network_name" {
  description = "Name of the GCP VPC network."
  type        = string
  default     = "multi-cloud-vpc"
}

variable "gcp_network_cidr" {
  description = "GCP VPC CIDR."
  type        = string
  default     = "10.1.0.0/16"

  validation {
    condition     = can(cidrsubnet(var.gcp_network_cidr, 0, 0))
    error_message = "Invalid CIDR block for GCP VPC network."
  }
}

variable "gcp_asn" {
  description = "GCP Side ASN for the GCP VPN Gateway."
  type        = string
  default     = "65001"
}
