variable "aws_region" {
  default = "us-east-2"
}

variable "aws_vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "aws_vpc_name" {
  default = "multi-cloud-vpc"
}

variable "aws_asn" {
  default = "64512"
}

variable "shared_key" {
  default = "mysecretkey123"
}

variable "aws_ssh_keypair_name" {
  type = string
}

variable "aws_ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "aws_ssh_keypair_exists" {
  type    = bool
  default = false
}

variable "aws_ami" {
  default = "ami-0199d4b5b8b4fde0e"
}

variable "aws_instance_type" {
  default = "t3a.micro"
}

locals {
  aws_azs            = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  aws_public_subnets = cidrsubnets(var.aws_vpc_cidr, 8, 8, 8)
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
    # gcp_01 = {
    #   bgp_asn    = var.gcp_asn
    #   ip_address = google_compute_ha_vpn_gateway.this.vpn_interfaces[0].ip_address
    # }
    # gcp_02 = {
    #   bgp_asn    = var.gcp_asn
    #   ip_address = google_compute_ha_vpn_gateway.this.vpn_interfaces[1].ip_address
    # }
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
  tunnel1_preshared_key = var.shared_key
  tunnel2_preshared_key = var.shared_key
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
