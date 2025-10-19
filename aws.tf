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

locals {
  aws_azs            = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  aws_public_subnets = cidrsubnets(var.aws_vpc_cidr, 8, 8, 8)
}

resource "random_password" "shared_key" {
  length           = 32
  override_special = "._"
}

module "aws_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.aws_vpc_name
  cidr = var.aws_vpc_cidr

  azs = local.aws_azs

  default_security_group_ingress = [
    {
      cidr_blocks = "0.0.0.0/0"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
    },
    {
      cidr_blocks = var.gcp_network_cidr
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
    },
    {
      cidr_blocks = var.aws_vpc_cidr
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
    },
    {
      cidr_blocks = "0.0.0.0/0"
      from_port   = -1
      to_port     = -1
      protocol    = "icmp"
    }
  ]

  default_security_group_egress = [
    {
      cidr_blocks = "0.0.0.0/0"
    }
  ]

  amazon_side_asn = var.aws_asn

  propagate_public_route_tables_vgw  = true
  propagate_private_route_tables_vgw = true

  customer_gateways = {
    for idx, interface in google_compute_ha_vpn_gateway.this.vpn_interfaces : "gcp-${idx}" => {
      bgp_asn    = var.gcp_asn
      ip_address = interface.ip_address
    }
  }
  public_subnets = local.aws_public_subnets

  enable_nat_gateway = false
  enable_vpn_gateway = true
}

resource "aws_vpn_connection" "this" {
  for_each = module.aws_vpc.this_customer_gateway

  customer_gateway_id   = each.value.id
  type                  = "ipsec.1"
  vpn_gateway_id        = module.aws_vpc.vgw_id
  tunnel1_preshared_key = random_password.shared_key.result
  tunnel2_preshared_key = random_password.shared_key.result
}

data "aws_key_pair" "this" {
  count    = var.aws_ssh_keypair_exists ? 1 : 0
  key_name = var.aws_ssh_keypair_name
}

resource "aws_key_pair" "this" {
  count      = var.aws_ssh_keypair_exists ? 0 : 1
  key_name   = var.aws_ssh_keypair_name
  public_key = file(var.aws_ssh_public_key_path)
}

resource "aws_instance" "this" {
  for_each = toset(module.aws_vpc.public_subnets)

  ami                         = var.aws_ami
  instance_type               = var.aws_instance_type
  associate_public_ip_address = true
  region                      = var.aws_region
  subnet_id                   = each.key
  key_name                    = var.aws_ssh_keypair_exists ? data.aws_key_pair.this[0].key_name : aws_key_pair.this[0].key_name
  vpc_security_group_ids = [
    module.aws_vpc.default_security_group_id,
  ]
  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              sudo yum install -y httpd
              sudo systemctl start httpd
              sudo systemctl enable httpd
              echo "Hello from AWS instance in subnet ${each.key}" > /var/www/html/index.html
              EOF
}

output "aws_instances_address" {
  value = {
    for instance in values(aws_instance.this) :
    instance.id => {
      public_ip  = instance.public_ip
      private_ip = instance.private_ip
    }
  }
}

output "vpn_tunnel_status" {
  description = "VPN tunnel information for debugging"
  value = {
    for name, conn in aws_vpn_connection.this : name => {
      id = conn.id
      tunnels = [
        {
          address    = conn.tunnel1_address
          bgp_ip     = conn.tunnel1_vgw_inside_address
          cgw_bgp_ip = conn.tunnel1_cgw_inside_address
        },
        {
          address    = conn.tunnel2_address
          bgp_ip     = conn.tunnel2_vgw_inside_address
          cgw_bgp_ip = conn.tunnel2_cgw_inside_address
        }
      ]
    }
  }
}
