locals {
  gcp_public_subnets = cidrsubnets(var.gcp_network_cidr, 8, 8, 8)
  gcp_tunnels_per_vpn = {
    for name, conn in aws_vpn_connection.this : name => {
      "tunnel1" = { peer_address = conn.tunnel1_address, vpn_gateway_interface = 0, peer_external_gateway_interface = 0 }
      "tunnel2" = { peer_address = conn.tunnel2_address, vpn_gateway_interface = 1, peer_external_gateway_interface = 1 }
    }
  }
  gcp_tunnels = merge([
    for vpn_name, tunnels_map in local.gcp_tunnels_per_vpn : {
      for t_name, t_val in tunnels_map :
      "${vpn_name}-${t_name}" => merge({ vpn_name = vpn_name }, t_val)
    }
  ]...)

  bgp_sessions = merge([
    for vpn_name, conn in aws_vpn_connection.this : {
      "${vpn_name}-tunnel1" = {
        ip_address      = conn.tunnel1_cgw_inside_address
        peer_ip_address = conn.tunnel1_vgw_inside_address
      }
      "${vpn_name}-tunnel2" = {
        ip_address      = conn.tunnel2_cgw_inside_address
        peer_ip_address = conn.tunnel2_vgw_inside_address
      }
    }
  ]...)
}

module "gcp_vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 12.0"

  project_id   = var.gcp_project_id
  network_name = var.gcp_network_name
  routing_mode = "GLOBAL"

  subnets = [
    for i in range(length(local.gcp_public_subnets)) :
    {
      subnet_name   = "${var.gcp_network_name}-public-${i}"
      subnet_ip     = local.gcp_public_subnets[i]
      subnet_region = var.gcp_region
    }
  ]

  ingress_rules = [
    {
      name        = "allow-icmp"
      description = "Allow ICMP from anywhere"
      direction   = "INGRESS"
      priority    = 1000
      allow       = [{ protocol = "icmp" }]
      ranges      = ["0.0.0.0/0"]
      target_tags = ["icmp-access"]
    },
    {
      name        = "allow-ssh"
      description = "Allow SSH from anywhere"
      direction   = "INGRESS"
      priority    = 1000
      allow       = [{ protocol = "tcp", ports = ["22"] }]
      ranges      = ["0.0.0.0/0"]
      target_tags = ["ssh-access"]
    },
    {
      name        = "allow-http-from-aws"
      description = "Allow HTTP from AWS VPC"
      direction   = "INGRESS"
      allow       = [{ protocol = "tcp", ports = ["80"] }]
      priority    = 1000
      ranges      = [var.aws_vpc_cidr]
      target_tags = ["http-access"]
    },
    {
      name        = "allow-http-from-gcp"
      description = "Allow HTTP from GCP VPC"
      direction   = "INGRESS"
      priority    = 1000
      allow       = [{ protocol = "tcp", ports = ["80"] }]
      ranges      = [var.gcp_network_cidr]
      target_tags = ["http-access"]
    },
  ]

  egress_rules = [
    {
      name        = "allow-all-egress"
      description = "Allow all egress traffic"
      direction   = "EGRESS"
      priority    = 1000
      allow       = [{ protocol = "all" }]
      ranges      = ["0.0.0.0/0"]
      target_tags = ["egress-inet"]
    },
  ]

  routes = [
    {
      name              = "egress-internet"
      description       = "route through IGW to access internet"
      destination_range = "0.0.0.0/0"
      tags              = "egress-inet"
      next_hop_internet = "true"
    },
  ]
}

resource "google_compute_ha_vpn_gateway" "this" {
  name    = "${var.gcp_network_name}-ha-vpn-gateway"
  network = module.gcp_vpc.network_name
  region  = var.gcp_region
}

resource "google_compute_external_vpn_gateway" "this" {
  for_each = local.gcp_tunnels_per_vpn

  name            = "${var.gcp_network_name}-ext-vpn-gateway-${each.key}"
  redundancy_type = "TWO_IPS_REDUNDANCY"

  dynamic "interface" {
    for_each = each.value
    content {
      id         = interface.value.vpn_gateway_interface
      ip_address = interface.value.peer_address
    }
  }
}

resource "google_compute_router" "this" {
  name    = "${var.gcp_network_name}-router"
  network = module.gcp_vpc.network_name
  region  = var.gcp_region
  bgp {
    asn               = var.gcp_asn
    advertise_mode    = "CUSTOM"
    advertised_groups = ["ALL_SUBNETS"]
  }
}


resource "google_compute_vpn_tunnel" "this" {
  for_each = local.gcp_tunnels

  name                            = "${var.gcp_network_name}-vpn-tunnel-${each.key}"
  region                          = var.gcp_region
  shared_secret                   = random_password.shared_key.result
  peer_external_gateway           = google_compute_external_vpn_gateway.this[each.value.vpn_name].id
  peer_external_gateway_interface = each.value.peer_external_gateway_interface
  router                          = google_compute_router.this.name
  vpn_gateway                     = google_compute_ha_vpn_gateway.this.id
  vpn_gateway_interface           = each.value.vpn_gateway_interface
}

resource "google_compute_router_interface" "this" {
  for_each = local.bgp_sessions

  name       = "${var.gcp_network_name}-router-if-${each.key}-${replace(each.value.ip_address, ".", "-")}"
  router     = google_compute_router.this.name
  vpn_tunnel = google_compute_vpn_tunnel.this[each.key].name
  ip_range   = "${each.value.ip_address}/30"
  region     = var.gcp_region
}

resource "google_compute_router_peer" "this" {
  for_each = local.bgp_sessions

  name            = "${var.gcp_network_name}-router-peer-${each.key}-${replace(each.value.ip_address, ".", "-")}"
  router          = google_compute_router.this.name
  region          = var.gcp_region
  interface       = google_compute_router_interface.this[each.key].name
  ip_address      = each.value.ip_address
  peer_ip_address = each.value.peer_ip_address
  peer_asn        = var.aws_asn
}

resource "google_compute_instance" "this" {
  for_each = toset(module.gcp_vpc.subnets_names)

  name         = "gcp-instance-${replace(each.key, "/", "-")}"
  machine_type = "e2-micro"
  zone         = "${var.gcp_region}-a"
  tags         = ["egress-inet", "ssh-access", "http-access", "icmp-access"]
  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }
  network_interface {
    network    = module.gcp_vpc.network_name
    subnetwork = each.key
    access_config {}
  }
  metadata_startup_script = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y nginx
              systemctl start nginx
              systemctl enable nginx
              echo "Hello from GCP instance in subnet ${each.key}" > /usr/share/nginx/html/index.html
              EOF
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_ed25519.pub")}"
  }
}

output "gcp_instances_address" {
  description = "Public and Private IPs of the GCP instance."
  value = {
    for instance in values(google_compute_instance.this) :
    instance.name => {
      public_ip  = instance.network_interface[0].access_config[0].nat_ip
      private_ip = instance.network_interface[0].network_ip
    }
  }
}

output "gcp_bgp_info" {
  description = "GCP BGP configuration"
  value = {
    router_name = google_compute_router.this.name
    asn         = google_compute_router.this.bgp[0].asn
    region      = google_compute_router.this.region
    peers = {
      for name, peer in google_compute_router_peer.this : name => {
        ip      = peer.ip_address
        peer_ip = peer.peer_ip_address
        asn     = peer.peer_asn
      }
    }
  }
}
