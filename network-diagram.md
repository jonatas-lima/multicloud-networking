# Multi-Cloud Network Diagram

## Architecture Overview

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

## Network Details

### AWS Configuration

| Propriedade | Valor |
|-------------|-------|
| **Region** | us-east-2 |
| **VPC CIDR** | 10.0.0.0/16 |
| **VPC Name** | multi-cloud-vpc |
| **ASN** | 64512 |
| **VPN Gateway** | Virtual Private Gateway |
| **Customer Gateways** | 2 (one per GCP HA VPN interface) |

#### AWS Subnets

| Availability Zone | CIDR | Type | Instance Type | Web Server |
|-------------------|------|------|---------------|------------|
| us-east-2a | 10.0.0.0/24 | Public | t3a.micro | Apache |
| us-east-2b | 10.0.1.0/24 | Public | t3a.micro | Apache |
| us-east-2c | 10.0.2.0/24 | Public | t3a.micro | Apache |

### GCP Configuration

| Propriedade | Valor |
|-------------|-------|
| **Region** | us-west1 |
| **VPC CIDR** | 10.1.0.0/16 |
| **VPC Name** | multi-cloud-vpc |
| **ASN** | 65001 |
| **Routing Mode** | GLOBAL |
| **VPN Gateway** | HA VPN Gateway (2 interfaces) |
| **Cloud Router** | With BGP (CUSTOM mode) |

#### GCP Subnets

| Zone | CIDR | Type | Instance Type | Web Server |
|------|------|------|---------------|------------|
| us-west1-a | 10.1.0.0/24 | Public | e2-micro | Nginx |
| us-west1-a | 10.1.1.0/24 | Public | e2-micro | Nginx |
| us-west1-a | 10.1.2.0/24 | Public | e2-micro | Nginx |

### VPN Configuration

| Propriedade | Valor |
|-------------|-------|
| **Protocol** | IPSec |
| **Routing Protocol** | eBGP (External BGP) |
| **Total Tunnels** | 4 (2 per Customer Gateway) |
| **Authentication** | Pre-shared key |
| **AWS ASN** | 64512 |
| **GCP ASN** | 65001 |
| **Route Advertisement** | Dynamic via BGP |
| **Redundancy** | Active-Active (HA) |

#### VPN Tunnels

| Tunnel | AWS Side | GCP Side | BGP Session |
|--------|----------|----------|-------------|
| VPN Connection 1 - Tunnel 1 | Customer Gateway 1 | HA VPN Interface 0 | Active |
| VPN Connection 1 - Tunnel 2 | Customer Gateway 1 | HA VPN Interface 0 | Active |
| VPN Connection 2 - Tunnel 1 | Customer Gateway 2 | HA VPN Interface 1 | Active |
| VPN Connection 2 - Tunnel 2 | Customer Gateway 2 | HA VPN Interface 1 | Active |

### Security Groups / Firewall Rules

| Rule | Protocol | Port | Source | Direction | Both Clouds |
|------|----------|------|--------|-----------|-------------|
| SSH Access | TCP | 22 | 0.0.0.0/0 | Ingress | Yes |
| HTTP from AWS | TCP | 80 | 10.0.0.0/16 | Ingress | Yes |
| HTTP from GCP | TCP | 80 | 10.1.0.0/16 | Ingress | Yes |
| ICMP/Ping | ICMP | - | 0.0.0.0/0 | Ingress | Yes |
| All Egress | All | All | 0.0.0.0/0 | Egress | Yes |

## Traffic Flow

### Cross-Cloud Communication

| Source | Destination | Path | Protocol |
|--------|-------------|------|----------|
| AWS Instances (10.0.x.x) | GCP Instances (10.1.x.x) | VPN Tunnels | IPSec + BGP |
| GCP Instances (10.1.x.x) | AWS Instances (10.0.x.x) | VPN Tunnels | IPSec + BGP |
| Any Instance | Internet | Direct (public IPs) | HTTP/HTTPS/SSH |

### High Availability

| Feature | Implementation | Benefit |
|---------|----------------|---------|
| Multiple Tunnels | 4 VPN tunnels total | Automatic failover if one tunnel fails |
| Redundant Gateways | 2 Customer Gateways + 2 VPN interfaces | No single point of failure |
| Dynamic Routing | BGP route advertisement | Automatic route updates |
| Geographic Distribution | AWS: 3 AZs, GCP: 1 Zone | Resilience to zone failures (AWS) |
