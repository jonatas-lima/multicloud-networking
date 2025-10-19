# Multi Cloud VPC Peering

## Objective

Multi cloud networking POC (Proof of Concept) between AWS and GCP using their VPN solutions and eBGP advertising. See the network diagram [here](./network-diagram.md).

## Security Notes

⚠️ **This is a POC with intentionally relaxed security for ease of testing:**

- SSH open to 0.0.0.0/0
- Shared VPN key in code
- `gcloud` CLI
- All instances have public IPs

## Prerequisites

- A valid and active AWS account
- A valid and active GCP account
- `terraform` (I use [tfenv](https://github.com/tfutils/tfenv) to manage my terraform versions)
- **(OPTIONAL)** [aws-vault](https://github.com/99designs/aws-vault)

## Network diagram

```mermaid
graph TB
    %% Internet
    subgraph Internet
        WEB[Internet]
    end

    %% AWS VPC
    subgraph AWS["AWS (us-east-2) - 10.0.0.0/16"]
        subgraph VPC_AWS[VPC: multi-cloud-vpc]
            VGW[Virtual Private Gateway<br/>ASN: 64512]

            subgraph AZ1["us-east-2a"]
                SUBNET_AWS_1[Public Subnet<br/>10.0.0.0/24]
                EC2_1[EC2 Instance<br/>t3a.micro<br/>Apache/HTTP]
            end

            subgraph AZ2["us-east-2b"]
                SUBNET_AWS_2[Public Subnet<br/>10.0.1.0/24]
                EC2_2[EC2 Instance<br/>t3a.micro<br/>Apache/HTTP]
            end

            subgraph AZ3["us-east-2c"]
                SUBNET_AWS_3[Public Subnet<br/>10.0.2.0/24]
                EC2_3[EC2 Instance<br/>t3a.micro<br/>Apache/HTTP]
            end

            CGW1[Customer Gateway 1<br/>GCP Interface 0]
            CGW2[Customer Gateway 2<br/>GCP Interface 1]
        end
    end

    %% VPN Connections
    subgraph VPN["VPN Connections (IPSec + BGP)"]
        VPN1_T1[VPN Conn 1 - Tunnel 1<br/>Shared Key]
        VPN1_T2[VPN Conn 1 - Tunnel 2<br/>Shared Key]
        VPN2_T1[VPN Conn 2 - Tunnel 1<br/>Shared Key]
        VPN2_T2[VPN Conn 2 - Tunnel 2<br/>Shared Key]
    end

    %% GCP VPC
    subgraph GCP["GCP (us-west1) - 10.1.0.0/16"]
        subgraph VPC_GCP[VPC: multi-cloud-vpc]
            HA_VPN[HA VPN Gateway<br/>2 Interfaces]
            CLOUD_ROUTER[Cloud Router<br/>ASN: 65001<br/>BGP Mode: CUSTOM]

            EXT_VPN1[External VPN Gateway 1<br/>AWS Tunnel IPs]
            EXT_VPN2[External VPN Gateway 2<br/>AWS Tunnel IPs]

            subgraph ZONE_GCP["us-west1-a"]
                SUBNET_GCP_1[Subnet<br/>10.1.0.0/24]
                GCE_1[Compute Instance<br/>e2-micro<br/>Nginx/HTTP]

                SUBNET_GCP_2[Subnet<br/>10.1.1.0/24]
                GCE_2[Compute Instance<br/>e2-micro<br/>Nginx/HTTP]

                SUBNET_GCP_3[Subnet<br/>10.1.2.0/24]
                GCE_3[Compute Instance<br/>e2-micro<br/>Nginx/HTTP]
            end
        end
    end

    %% AWS Internal Connections
    EC2_1 --> SUBNET_AWS_1
    EC2_2 --> SUBNET_AWS_2
    EC2_3 --> SUBNET_AWS_3
    SUBNET_AWS_1 --> VGW
    SUBNET_AWS_2 --> VGW
    SUBNET_AWS_3 --> VGW
    CGW1 --> VGW
    CGW2 --> VGW

    %% VPN Connections - AWS to GCP
    CGW1 --> VPN1_T1
    CGW1 --> VPN1_T2
    CGW2 --> VPN2_T1
    CGW2 --> VPN2_T2

    VPN1_T1 -->|eBGP| EXT_VPN1
    VPN1_T2 -->|eBGP| EXT_VPN1
    VPN2_T1 -->|eBGP| EXT_VPN2
    VPN2_T2 -->|eBGP| EXT_VPN2

    EXT_VPN1 --> HA_VPN
    EXT_VPN2 --> HA_VPN
    HA_VPN --> CLOUD_ROUTER

    %% GCP Internal Connections
    GCE_1 --> SUBNET_GCP_1
    GCE_2 --> SUBNET_GCP_2
    GCE_3 --> SUBNET_GCP_3
    SUBNET_GCP_1 --> CLOUD_ROUTER
    SUBNET_GCP_2 --> CLOUD_ROUTER
    SUBNET_GCP_3 --> CLOUD_ROUTER

    %% Internet Access
    WEB --> EC2_1
    WEB --> EC2_2
    WEB --> EC2_3
    WEB --> GCE_1
    WEB --> GCE_2
    WEB --> GCE_3

    %% Styling
    classDef awsStyle fill:#FF9900,stroke:#232F3E,stroke-width:2px,color:#000
    classDef gcpStyle fill:#4285F4,stroke:#1967D2,stroke-width:2px,color:#fff
    classDef vpnStyle fill:#00C853,stroke:#00796B,stroke-width:2px,color:#fff

    class VPC_AWS,VGW,CGW1,CGW2,EC2_1,EC2_2,EC2_3,SUBNET_AWS_1,SUBNET_AWS_2,SUBNET_AWS_3 awsStyle
    class VPC_GCP,HA_VPN,CLOUD_ROUTER,EXT_VPN1,EXT_VPN2,GCE_1,GCE_2,GCE_3,SUBNET_GCP_1,SUBNET_GCP_2,SUBNET_GCP_3 gcpStyle
    class VPN1_T1,VPN1_T2,VPN2_T1,VPN2_T2 vpnStyle
```

## How to run

1. Export your AWS variables (or use `aws-vault`). I only tested in `us-east-2`.

    ```bash
    AWS_ACCESS_KEY_ID=REDACTED
    AWS_SECRET_ACCESS_KEY=REDACTED
    AWS_REGION=us-east-2
    ```

1. Configure `gcloud` auth:

    ```bash
    gcloud init
    gcloud auth application-default login
    ```

1. Initialize the project:

    ```bash
    terraform init
    ```

1. Configure your variables (the only ones that are required are the SSH related variables) in `terraform.tfvars`

    ```hcl
    # terraform.tfvars example
    aws_ssh_keypair_name   = "ssh"
    aws_ssh_keypair_exists = true
    aws_region             = "us-east-2"
    ```

1. Spin up the infra:

    ```bash
    make all
    ```

1. SSH into one of the 6 instances provisioned and `curl` and `ping` the other instances through the private IP, it should be working!

## Terraform Docs

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_google"></a> [google](#requirement\_google) | 7.7.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | 3.7.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.17.0 |
| <a name="provider_google"></a> [google](#provider\_google) | 7.7.0 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.7.2 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_aws_vpc"></a> [aws\_vpc](#module\_aws\_vpc) | terraform-aws-modules/vpc/aws | n/a |
| <a name="module_gcp_vpc"></a> [gcp\_vpc](#module\_gcp\_vpc) | terraform-google-modules/network/google | ~> 12.0 |

## Resources

| Name | Type |
|------|------|
| [aws_instance.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_key_pair.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/key_pair) | resource |
| [aws_vpn_connection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpn_connection) | resource |
| [google_compute_external_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_external_vpn_gateway) | resource |
| [google_compute_ha_vpn_gateway.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_ha_vpn_gateway) | resource |
| [google_compute_instance.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_instance) | resource |
| [google_compute_router.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_router) | resource |
| [google_compute_router_interface.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_router_interface) | resource |
| [google_compute_router_peer.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_router_peer) | resource |
| [google_compute_vpn_tunnel.this](https://registry.terraform.io/providers/hashicorp/google/7.7.0/docs/resources/compute_vpn_tunnel) | resource |
| [random_password.shared_key](https://registry.terraform.io/providers/hashicorp/random/3.7.2/docs/resources/password) | resource |
| [aws_key_pair.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/key_pair) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_ssh_keypair_name"></a> [aws\_ssh\_keypair\_name](#input\_aws\_ssh\_keypair\_name) | Name of the AWS SSH key pair. | `string` | n/a | yes |
| <a name="input_aws_ami"></a> [aws\_ami](#input\_aws\_ami) | AMI ID for the AWS EC2 instances. | `string` | `"ami-0199d4b5b8b4fde0e"` | no |
| <a name="input_aws_asn"></a> [aws\_asn](#input\_aws\_asn) | Amazon Side ASN for the AWS VPN Gateway. | `string` | `"64512"` | no |
| <a name="input_aws_instance_type"></a> [aws\_instance\_type](#input\_aws\_instance\_type) | Instance type for the AWS EC2 instances. | `string` | `"t3a.micro"` | no |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS region. | `string` | `"us-east-2"` | no |
| <a name="input_aws_ssh_keypair_exists"></a> [aws\_ssh\_keypair\_exists](#input\_aws\_ssh\_keypair\_exists) | Set to true if the AWS SSH key pair already exists. | `bool` | `false` | no |
| <a name="input_aws_ssh_public_key_path"></a> [aws\_ssh\_public\_key\_path](#input\_aws\_ssh\_public\_key\_path) | Path to the AWS SSH public key. Used to login to EC2 instances. | `string` | `"~/.ssh/id_ed25519.pub"` | no |
| <a name="input_aws_vpc_cidr"></a> [aws\_vpc\_cidr](#input\_aws\_vpc\_cidr) | AWS VPC CIDR. | `string` | `"10.0.0.0/16"` | no |
| <a name="input_aws_vpc_name"></a> [aws\_vpc\_name](#input\_aws\_vpc\_name) | Name of the AWS VPC. | `string` | `"multi-cloud-vpc"` | no |
| <a name="input_gcp_asn"></a> [gcp\_asn](#input\_gcp\_asn) | GCP Side ASN for the GCP VPN Gateway. | `string` | `"65001"` | no |
| <a name="input_gcp_network_cidr"></a> [gcp\_network\_cidr](#input\_gcp\_network\_cidr) | GCP VPC CIDR. | `string` | `"10.1.0.0/16"` | no |
| <a name="input_gcp_network_name"></a> [gcp\_network\_name](#input\_gcp\_network\_name) | Name of the GCP VPC network. | `string` | `"multi-cloud-vpc"` | no |
| <a name="input_gcp_project_id"></a> [gcp\_project\_id](#input\_gcp\_project\_id) | GCP Project ID. | `string` | `"multi-region-network"` | no |
| <a name="input_gcp_region"></a> [gcp\_region](#input\_gcp\_region) | GCP region for the resources. | `string` | `"us-west1"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_aws_instances_address"></a> [aws\_instances\_address](#output\_aws\_instances\_address) | n/a |
| <a name="output_gcp_bgp_info"></a> [gcp\_bgp\_info](#output\_gcp\_bgp\_info) | GCP BGP configuration |
| <a name="output_gcp_instances_address"></a> [gcp\_instances\_address](#output\_gcp\_instances\_address) | n/a |
| <a name="output_vpn_tunnel_status"></a> [vpn\_tunnel\_status](#output\_vpn\_tunnel\_status) | VPN tunnel information for debugging |
<!-- END_TF_DOCS -->
