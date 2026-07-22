# Nomad infrastructure

Infrastructure-as-Code for deploying a co-located HashiCorp Consul and Nomad
cluster on AWS using Terraform and Ansible.

We tested this infrastructure with the following versions:

| Software | Version |
|----------|---------|
| HashiCorp Nomad | 2.0.4 |
| HashiCorp Consul | 2.0.1 |
| Terraform | ≥ 1.0 |
| AWS Terraform provider | ~> 5.0 |
| Ansible | ≥ 2.14 |
| CNI plugins | 1.9.1 |
| Docker CE | latest |
| Ubuntu | 24.04 LTS |

## Overview

This project provisions a production-ready cluster of three servers and two
clients on AWS or locally with Multipass. Every node runs co-located Consul and
Nomad agents, providing a service-discovery and service-mesh layer (Consul)
alongside a workload-orchestration layer (Nomad) on the same infrastructure.

Repo purpose:

- Education engineers and tech writers can spin up an AWS or Multipass cluster for learning the products and testing features.
- Use in conjunction with a tutorial. Modify tutorials to instruct user what playbook to run to create environment for tutorial.
- Use to spin up a cluster in Instruqt sandbox (TBD since full cluster creation takes 15 mins).

Goals:

- Definable, repeatable infrastructure creation/destroy with Terraform
- Definable, repeatable cluster creation/teardown with Ansible
- Modular approach with top-level playbooks that call playbooks relevant to the
use case.
- Expandable in the future to add more playbooks for new scenarios.

**[Complete Deployment Guide](DEPLOY_CLUSTER_GUIDE.MD)** — Step-by-step instructions for deploying your cluster.

### What gets deployed

| Layer | Technology | Version |
|-------|-----------|---------|
| Service discovery & mesh | HashiCorp Consul | 2.0.2 |
| Workload orchestration | HashiCorp Nomad | 2.0.4 |
| Container runtime | Docker CE | latest |
| Container networking | CNI plugins | (clients only) |
| DNS forwarding | dnsmasq | (all nodes) |
| Operating system | Ubuntu 24.04 LTS | latest AMI |

### Key features

- **Co-located cluster**: Consul and Nomad agents run side-by-side on every node
- **Consul Cloud Auto-Join**: Consul discovers peers automatically using the `AutoJoinRole` EC2 tag — no hardcoded IPs
- **Nomad static join**: Nomad uses private IPs from the Ansible inventory for `server_join.retry_join`
- **IAM-powered discovery**: EC2 instance profiles grant least-privilege `ec2:DescribeInstances` access for Consul Cloud Auto-Join
- **TLS by default**: Consul and Nomad both enable TLS by default (`consul_tls_enabled: true`, `nomad_tls_enabled: true`). Certificates are self-signed by the `tls` role and distributed automatically. Consul serves plain HTTP on `127.0.0.1:8500` (loopback only) alongside HTTPS on `0.0.0.0:8443`; Nomad's HTTP and RPC layers are TLS-only.
- **ACL-ready**: Consul ACLs are enabled on servers by default. Nomad ACLs are enabled on all nodes by default. Each has a dedicated bootstrap playbook.
- **Consul service discovery**: Nomad integrates with Consul using Workload Identities (JWT-based, Nomad 1.7+) with no shared static tokens. Nomad services and tasks obtain scoped Consul ACL tokens automatically.
- **dnsmasq DNS forwarding**: Every node runs dnsmasq to forward `.global` DNS queries to the local Consul agent, enabling service address resolution for all processes
- **CNI + Docker**: Clients install CNI plugins and Docker CE for containerized workloads
- **Idempotent**: Safe to re-run Terraform and Ansible repeatedly

## Architecture

```mermaid
graph TB
    Internet((Internet))
    IGW[Internet Gateway]

    subgraph VPC["AWS VPC (10.0.0.0/16)"]
        subgraph Subnet["Public Subnet (10.0.1.0/24)"]
            subgraph S1["Server 1 · t3.medium · 50 GB gp3"]
                CS1[Consul Server]
                NS1[Nomad Server]
                DS1[Docker]
            end
            subgraph S2["Server 2 · t3.medium · 50 GB gp3"]
                CS2[Consul Server]
                NS2[Nomad Server]
                DS2[Docker]
            end
            subgraph S3["Server 3 · t3.medium · 50 GB gp3"]
                CS3[Consul Server]
                NS3[Nomad Server]
                DS3[Docker]
            end
            subgraph C1["Client 1 · t3.medium · 50 GB gp3"]
                CC1[Consul Client]
                NC1[Nomad Client]
                DC1[Docker + CNI]
            end
            subgraph C2["Client 2 · t3.medium · 50 GB gp3"]
                CC2[Consul Client]
                NC2[Nomad Client]
                DC2[Docker + CNI]
            end
        end
    end

    Internet --> IGW --> Subnet
```

### Node roles

| Node type | Consul agent | Nomad agent | Docker | CNI plugins |
|-----------|-------------|------------|--------|-------------|
| Server (×3) | Server | Server | ✓ | — |
| Client (×2) | Client | Client | ✓ | ✓ |

### Cluster discovery

| Service | Discovery method |
|---------|----------------|
| Consul | AWS Cloud Auto-Join — queries EC2 API for instances tagged `AutoJoinRole=server` |
| Nomad | Static `server_join.retry_join` — private IPs from the `[servers]` inventory group |

## Project structure

```
nomad-infra/
├── README.md                             # This file
├── DEPLOY_CLUSTER_GUIDE.MD                         # Full deployment walkthrough
├── AGENTS.md                             # Coding agent guidelines
├── terraform/
│   └── aws/
│       ├── main.tf                       # Provider configuration
│       ├── variables.tf                  # Input variables
│       ├── outputs.tf                    # Output values
│       ├── ami.tf                        # Ubuntu 24.04 AMI lookup
│       ├── network.tf                    # VPC, subnet, security group
│       ├── compute.tf                    # EC2 instances + inventory generation
│       ├── iam.tf                        # IAM role for cloud auto-join
│       ├── keypair.tf                    # SSH key pair
│       ├── inventory.tpl                 # Ansible inventory template
│       ├── terraform.tfvars.example      # Variable examples
│       └── README.md                     # Terraform reference
└── ansible/
    ├── ansible.cfg                       # Ansible configuration
    ├── requirements.yaml                 # Galaxy roles (geerlingguy.docker)
    ├── inventory.ini                     # Auto-generated by Terraform
    ├── ssh_key.pem                       # Auto-generated SSH private key
    ├── deploy_consul.yaml                # Use case: Consul cluster only
    ├── deploy_nomad.yaml                 # Use case: Nomad cluster only
    ├── deploy_consul_nomad_sd.yaml       # Use case: Consul + Nomad + service discovery
    ├── deploy_consul_nomad_wi.yaml       # Use case: Consul + Nomad + SD + workload identity
    ├── teardown.yaml                     # Teardown playbook
    ├── set-cluster-env.sh                # Source to set CONSUL/NOMAD env vars
    ├── unset-cluster-env.sh              # Source to unset CONSUL/NOMAD env vars
    ├── tokens/                           # ACL bootstrap token files (auto-created, git-ignored)
    ├── playbooks/                        # Sub-playbooks (imported by use case entrypoints)
    │   ├── consul_servers.yaml           # Consul server configuration
    │   ├── consul_clients.yaml           # Consul client configuration
    │   ├── consul_acl_bootstrap.yaml     # Consul ACL bootstrap
    │   ├── consul_acl_deny_anonymous.yaml    # Deny Consul anonymous token
    │   ├── consul_nomad_integration.yaml # Consul-Nomad integration orchestrator
    │   ├── consul_nomad_service_discovery.yaml  # Consul ACL policies + Nomad tokens
    │   ├── consul_nomad_workload_identity.yaml  # JWT auth method + binding rules
    │   ├── nomad_servers.yaml            # Nomad server configuration
    │   ├── nomad_clients.yaml            # Nomad client configuration
    │   ├── nomad_acl_bootstrap.yaml      # Nomad ACL bootstrap
    │   ├── dnsmasq.yaml                  # dnsmasq DNS forwarding
    │   ├── cluster_summary.yaml          # Cluster status and token summary
    │   └── common_setup.yaml             # Shared host pre-tasks
    ├── PLAYBOOKS-README.md               # Playbook reference
    ├── BOOTSTRAP_ACL_EXAMPLE.md          # ACL bootstrap walkthrough
    ├── README-SECURITY-GROUP.md          # Security group hardening guide
    └── roles/
        ├── common/                       # Base system setup
        ├── cni/                          # CNI plugins (clients only)
        ├── hashicorp_release/            # HashiCorp binary installer
        ├── helper/                       # File and package utilities
        ├── consul/                       # Consul install and configure
        ├── nomad/                        # Nomad install and configure
        ├── nomad_consul/                 # Consul ACL resources for Nomad integration
        └── tls/                          # TLS certificate generation
```

## Sensitive files

The following files are git-ignored and must never be committed:

| File | Contents |
|------|----------|
| `ansible/ssh_key.pem` | SSH private key for all EC2 instances |
| `ansible/.tls/` | Generated TLS certificates |
| `ansible/tokens/consul-bootstrap-token-output.txt` | Consul management ACL token |
| `ansible/tokens/consul-bootstrap-secret-id.txt` | Consul ACL SecretID |
| `ansible/tokens/nomad-bootstrap-token-output.txt` | Nomad management ACL token |
| `ansible/tokens/nomad-bootstrap-secret-id.txt` | Nomad ACL SecretID |
| `ansible/tokens/nomad-consul-server-token-output.txt` | Full Consul token output for Nomad server agents |
| `ansible/tokens/nomad-consul-server-secret-id.txt` | Consul token SecretID for Nomad server agents |
| `ansible/tokens/nomad-consul-client-token-output.txt` | Full Consul token output for Nomad client agents |
| `ansible/tokens/nomad-consul-client-secret-id.txt` | Consul token SecretID for Nomad client agents |
| `terraform/aws/terraform.tfvars` | AWS credentials and configuration |

For cleanup instructions, refer to [DEPLOY_CLUSTER_GUIDE.MD](DEPLOY_CLUSTER_GUIDE.MD#cleanup).
