# Nomad plus Consul cluster deployment guide

This guide provides step-by-step instructions for deploying a co-located HashiCorp Consul and Nomad cluster on AWS.

## Overview

The deployment has two phases:

1. **Terraform** — Provisions AWS infrastructure (approximately five minutes)
2. **Ansible** — Installs and configures Consul and Nomad (approximately 10–15 minutes)

> **Working through a [Nomad tutorial](https://developer.hashicorp.com/nomad/tutorials)?**
> Refer to [_context/wiki/nomad-tutorial-scenario-mapping.md](_context/wiki/nomad-tutorial-scenario-mapping.md)
> for which use case below satisfies each tutorial's prerequisites.

```mermaid
flowchart TD
    START([Start]) --> TF1[Edit terraform.tfvars]
    TF1 --> TF2[terraform init]
    TF2 --> TF3[terraform plan]
    TF3 --> TF4[terraform apply]
    TF4 --> INV[/inventory.ini generated/]
    INV --> DEPS[ansible-galaxy install -r requirements.yaml]
    DEPS --> PICK{Choose use case}

    PICK -->|"0 · Get Started (single-node)"| UC0[deploy_get_started.yaml]
    PICK -->|"1 · Consul only"| UC1[deploy_consul.yaml]
    PICK -->|"2 · Nomad only"| UC2[deploy_nomad.yaml]
    PICK -->|"3 · + service discovery"| UC3[deploy_consul_nomad_sd.yaml]
    PICK -->|"4 · + workload identity"| UC4[deploy_consul_nomad_wi.yaml]
    PICK -->|"5 · + service mesh"| UC5[deploy_consul_nomad_mesh.yaml]
    PICK -->|"6 · Nomad + Vault"| UC6[deploy_nomad_vault.yaml]

    UC0 --> P0A[common_setup]
    P0A --> P0B[get_started]
    P0B --> P0Z([completion banner])

    UC1 --> P1A[common_setup]
    P1A --> P1B[consul_servers]
    P1B --> P1C[consul_clients]
    P1C --> P1D[consul_acl_bootstrap]
    P1D --> P1E[consul_dns_token]
    P1E --> P1F[dnsmasq]
    P1F --> P1G[consul_acl_deny_anonymous]
    P1G --> P1Z([cluster_summary])

    UC2 --> P2A[common_setup]
    P2A --> P2B[nomad_servers]
    P2B --> P2C[nomad_clients]
    P2C --> P2D[nomad_acl_bootstrap]
    P2D --> P2Z([cluster_summary])

    UC3 --> P3A[common_setup]
    P3A --> P3B[consul_servers]
    P3B --> P3C[consul_clients]
    P3C --> P3D[consul_acl_bootstrap]
    P3D --> P3E[consul_dns_token]
    P3E --> P3F[dnsmasq]
    P3F --> P3G[consul_acl_deny_anonymous]
    P3G --> P3H[nomad_servers]
    P3H --> P3I[nomad_clients]
    P3I --> P3J[nomad_acl_bootstrap]
    P3J --> P3K[consul_nomad_service_discovery]
    P3K --> P3Z([cluster_summary])

    UC4 --> P4A[common_setup]
    P4A --> P4B[consul_servers]
    P4B --> P4C[consul_clients]
    P4C --> P4D[consul_acl_bootstrap]
    P4D --> P4E[consul_dns_token]
    P4E --> P4F[dnsmasq]
    P4F --> P4G[consul_acl_deny_anonymous]
    P4G --> P4H[nomad_servers]
    P4H --> P4I[nomad_clients]
    P4I --> P4J[nomad_acl_bootstrap]
    P4J --> P4K[consul_nomad_service_discovery]
    P4K --> P4L[consul_nomad_workload_identity]
    P4L --> P4Z([cluster_summary])

    UC5 --> P5A[common_setup]
    P5A --> P5B[consul_servers]
    P5B --> P5C[consul_clients]
    P5C --> P5D[consul_acl_bootstrap]
    P5D --> P5E[consul_dns_token]
    P5E --> P5F[dnsmasq]
    P5F --> P5G[consul_acl_deny_anonymous]
    P5G --> P5H[nomad_servers]
    P5H --> P5I[nomad_clients]
    P5I --> P5J[nomad_acl_bootstrap]
    P5J --> P5K[consul_nomad_service_discovery]
    P5K --> P5L[consul_nomad_workload_identity]
    P5L --> P5M[consul_nomad_service_mesh]
    P5M --> P5Z([cluster_summary])

    UC6 --> P6A[common_setup]
    P6A --> P6B[nomad_servers]
    P6B --> P6C[nomad_clients]
    P6C --> P6D[nomad_acl_bootstrap]
    P6D --> P6E[vault_servers]
    P6E --> P6F[nomad_vault_integration]
    P6F --> P6Z([cluster_summary])
```

## Deployment workflows

Each of the following use cases is a complete end-to-end checklist. Steps 1–4 are identical
for all use cases. Follow only the checklist for your use case — each step links
to the detailed section in this guide.

### Use case Get Started: single-node Nomad agent (no Consul, no TLS, no ACLs)

1. **[Install prerequisites](#prerequisites)**
1. **[Configure AWS credentials](#aws-credentials)**
1. **Set `server_count = 1` and `client_count = 0` in `terraform.tfvars`, then [provision infrastructure](#phase-1-provision-infrastructure-terraform)**
1. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
1. **[Deploy the single-node agent](#option-get-started-single-node-nomad-agent----deploy_get_startedyaml)**
1. **Work through the [Get Started tutorials](https://developer.hashicorp.com/nomad/tutorials/get-started)**
1. **[Clean up when done](#cleanup)**

---

### Use case A: Consul cluster only

1. **[Install prerequisites](#prerequisites)**
1. **[Configure AWS credentials](#aws-credentials)**
1. **[Provision infrastructure](#phase-1-provision-infrastructure-terraform)**
1. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
1. **[Deploy the Consul cluster](#option-a-consul-cluster-only----deploy_consulyaml)**
1. **[Export environment variables](#post-deployment-set-environment-variables)**
1. **[Verify the cluster](#verify-consul)**
1. **[Clean up when done](#cleanup)**

---

### Use case B: Nomad cluster only

1. **[Install prerequisites](#prerequisites)**
2. **[Configure AWS credentials](#aws-credentials)**
3. **[Provision infrastructure](#phase-1-provision-infrastructure-terraform)**
4. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
5. **[Deploy the Nomad cluster](#option-b-nomad-cluster-only----deploy_nomadyaml)**
6. **[Export environment variables](#post-deployment-set-environment-variables)**
7. **[Verify the cluster](#verify-nomad)**
8. **[Clean up when done](#cleanup)**
---

### Use case C: Consul + Nomad with service discovery

1. **[Install prerequisites](#prerequisites)**
2. **[Configure AWS credentials](#aws-credentials)**
3. **[Provision infrastructure](#phase-1-provision-infrastructure-terraform)**
4. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
5. **[Deploy the cluster](#option-c-consul--nomad-with-service-discovery----deploy_consul_nomad_sdyaml)**
6. **[Export environment variables](#post-deployment-set-environment-variables)**
7. **[Verify the cluster](#post-deployment-verification)**
8. **[Clean up when done](#cleanup)**

---

### Use case D: Consul + Nomad with service discovery and workload identity

1. **[Install prerequisites](#prerequisites)**
2. **[Configure AWS credentials](#aws-credentials)**
3. **[Provision infrastructure](#phase-1-provision-infrastructure-terraform)**
4. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
5. **[Deploy the cluster](#option-d-consul--nomad-with-service-discovery-and-workload-identity----deploy_consul_nomad_wiyaml)**
6. **[Export environment variables](#post-deployment-set-environment-variables)**
7. **[Verify the cluster](#post-deployment-verification)**
8. **[Clean up when done](#cleanup)**

---

### Use case E: Consul + Nomad with service discovery, workload identity, service mesh, and API gateway

1. **[Install prerequisites](#prerequisites)**
2. **[Configure AWS credentials](#aws-credentials)**
3. **Set `ingress_client_count = 1` in `terraform.tfvars`, then [provision infrastructure](#phase-1-provision-infrastructure-terraform)** — this Option is the only one that needs the dedicated public ingress client; every other Option should leave it at `0`
4. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
5. **[Deploy the cluster](#option-e-consul--nomad-with-service-discovery-workload-identity-and-service-mesh----deploy_consul_nomad_meshyaml)**
6. **[Export environment variables](#post-deployment-set-environment-variables)**
7. **[Deploy the service mesh apps and API Gateway](nomad-jobs/consul-mesh/README.md)**
8. **[Verify the cluster](#post-deployment-verification)**
9. **[Clean up when done](#cleanup)**

---

### Use case F: Nomad + Vault with workload identity (no Consul)

1. **[Install prerequisites](#prerequisites)**
2. **[Configure AWS credentials](#aws-credentials)**
3. **[Provision infrastructure](#phase-1-provision-infrastructure-terraform)**
4. **[Install Ansible Galaxy roles](#phase-2-cluster-configuration-ansible)**
5. **[Deploy the cluster](#option-f-nomad--vault-with-workload-identity----deploy_nomad_vaultyaml)**
6. **[Export environment variables](#post-deployment-set-environment-variables)**
7. **[Verify the cluster](#post-deployment-verification)**
8. **[Clean up when done](#cleanup)**

---

## Prerequisites

| Tool | Minimum version | Verify |
|------|----------------|--------|
| Terraform | 1.0 | `terraform version` |
| Ansible | 2.14 | `ansible --version` |
| AWS CLI | any | `aws sts get-caller-identity` |

Ansible requires the locale encoding on the control machine (where you run `ansible-playbook`) to be UTF-8. Any locale works — `it_IT.UTF-8`, `fr_FR.UTF-8`, `en_US.UTF-8`, and so on — as long as the `.UTF-8` charset suffix is present. The playbooks themselves are locale-agnostic.

Verify your locale before running any playbook:

```bash
locale
```

If `LANG` or `LC_ALL` is missing the `.UTF-8` suffix (for example, `it_IT` instead of `it_IT.UTF-8`), append it:

```bash
export LANG="${LANG}.UTF-8"   # for example: it_IT  →  it_IT.UTF-8
export LC_ALL="${LANG}"
```

Or set an explicit value if `LANG` is unset.

```bash
export LANG=it_IT.UTF-8
export LC_ALL=it_IT.UTF-8
```

Install Ansible Galaxy roles before running any playbook:

```bash
cd ansible
ansible-galaxy install -r requirements.yaml
```

### AWS credentials

This step is only required for the AWS infrastructure option.

```bash
# Option 1: AWS CLI
aws configure

# Option 2: Environment variables
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="us-east-2"

# Option 3: Named profile
export AWS_PROFILE="your-profile-name"

# Verify
aws sts get-caller-identity
```

### Nomad, Consul, and Vault CLIs

If you plan to interact with the cluster from your terminal, install the Nomad
CLI and optionally Consul and Vault.

- [Install Nomad CLI
  instructions](https://developer.hashicorp.com/nomad/install)
- [Install Consul CLI instructions](https://developer.hashicorp.com/consul/install)
- [Install Vault CLI instructions](https://developer.hashicorp.com/vault/install)

---

## Configuration reference

### Terraform variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region |
| `project_name` | `nomad-consul` | Resource name prefix |
| `owner` | `devops-team` | Owner tag |
| `environment` | `dev` | Environment tag |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `subnet_cidr` | `10.0.1.0/24` | Public subnet CIDR |
| `allowed_ssh_cidr` | `0.0.0.0/0` | CIDR allowed for SSH |
| `server_count` | `3` | Number of server EC2 instances |
| `client_count` | `2` | Number of (internal) client EC2 instances |
| `ingress_client_count` | `0` | Number of dedicated public ingress client EC2 instances — runs the Consul API Gateway for Option E; the only client whose security group opens app-facing ports like `8447`. Terraform provisioning is shared across every Option and runs before you pick one, so this defaults to `0` and must be set to `1` explicitly in `terraform.tfvars` before provisioning if you intend to deploy Option E — see that section. See also [`_context/wiki/dedicated-ingress-node-plan.md`](_context/wiki/dedicated-ingress-node-plan.md). |
| `server_instance_type` | `t3.medium` | Server EC2 instance type |
| `client_instance_type` | `t3.medium` | Client EC2 instance type (used for both internal and ingress clients) |

Always set `allowed_ssh_cidr` to your specific IP address or network range.

### Ansible variables — Consul

Defaults: [`ansible/roles/consul/defaults/main.yaml`](ansible/roles/consul/defaults/main.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `consul_binary_version` | `2.0.2` | Consul release to install |
| `consul_datacenter` | `dc1` | Datacenter name |
| `consul_server_enabled` | `false` | Enable server mode |
| `consul_server_bootstrap_expect` | `3` | Quorum size |
| `consul_cloud_auto_join_enabled` | `false` | Enable AWS Cloud Auto-Join |
| `consul_acl_enabled` | `false` | Enable ACLs |
| `consul_tls_enabled` | `true` | Enable TLS |
| `consul_edition` | `oss` | `oss` or `enterprise` — see [Optional: Nomad/Consul Enterprise licensing](#optional-nomadconsul-enterprise-licensing) |

### Ansible variables — Nomad

Defaults: [`ansible/roles/nomad/defaults/main.yaml`](ansible/roles/nomad/defaults/main.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_binary_version` | `2.0.4` | Nomad release to install |
| `nomad_server_enabled` | `false` | Enable server mode |
| `nomad_server_bootstrap_expect` | `3` | Quorum size |
| `nomad_client_enabled` | `false` | Enable client mode |
| `nomad_cloud_auto_join_enabled` | `false` | Enable AWS Cloud Auto-Join |
| `nomad_acl_enabled` | `false` | Enable ACLs |
| `nomad_tls_enabled` | `true` | Enable TLS |
| `nomad_log_level` | `DEBUG` | Log level |
| `nomad_edition` | `oss` | `oss` or `enterprise` — see [Optional: Nomad/Consul Enterprise licensing](#optional-nomadconsul-enterprise-licensing) |

### Ansible variables — Vault

Defaults: [`ansible/roles/vault/defaults/main.yaml`](ansible/roles/vault/defaults/main.yaml)

| Variable | Default | Description |
|----------|---------|-------------|
| `vault_binary_version` | `1.20.1` | Vault release to install |
| `vault_tls_enabled` | `true` | Enable TLS |
| `vault_cloud_auto_join_enabled` | `false` | Enable AWS Cloud Auto-Join for Raft `retry_join` |

Vault uses Raft integrated storage — no external storage backend or Consul dependency.

---

## Network security

The security group allows:

- **SSH (22)**: From `allowed_ssh_cidr`. The default value `0.0.0.0/0` is not appropriate for production. Set this to your specific IP address or network range.
- **Consul HTTP API/UI (8500)**: Plain HTTP, loopback only (`127.0.0.1`) — not reachable from the security group. Used for local automation and Nomad's local `consul {}` integration.
- **Consul HTTPS API/UI (8443)**: From `0.0.0.0/0`. TLS is enabled by default. Restrict this in production.
- **Nomad HTTPS API/UI (4646)**: From `0.0.0.0/0`. TLS is enabled by default (Nomad has no plain-HTTP loopback exception). Restrict this in production.
- **All internal traffic**: Between instances sharing the security group
- **Egress**: All outbound traffic allowed

Refer to [ansible/README-SECURITY-GROUP.md](ansible/README-SECURITY-GROUP.md) for hardening guidance.

### Default open ports

| Port | Protocol | Service | Accessible from |
|------|----------|---------|----------------|
| 22 | TCP | SSH | `allowed_ssh_cidr` |
| 8500 | TCP | Consul HTTP API & UI (plain HTTP) | Loopback only (`127.0.0.1`) |
| 8443 | TCP | Consul HTTPS API & UI | `0.0.0.0/0` |
| 8300 | TCP | Consul RPC | Internal (security group) |
| 8301 | TCP/UDP | Consul Serf LAN | Internal (security group) |
| 4646 | TCP | Nomad HTTP(S) API & UI | `0.0.0.0/0` |
| all | all | Internal cluster traffic | Internal (security group) |

### IAM permissions

Every EC2 instance receives an IAM instance profile with the following permissions for Consul Cloud Auto-Join:

- `ec2:DescribeInstances`
- `ec2:DescribeTags`
- `autoscaling:DescribeAutoScalingGroups`

---

## Phase 1: Provision infrastructure (Terraform)

### Step 1: Configure variables

```bash
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` to use values specific to your deployment. This guide
was tested with an Ubuntu 24.04 AMI.

**Important values:**

- `aws_region`
- `owner`
- `allowed_ssh_cidr`
- `ami_owner`
- `ami_name_filter`


```hcl
aws_region           = "<aws-region>"
project_name         = "nomad-consul"
owner                = "<your-name>"
environment          = "dev"

# Network configuration
vpc_cidr             = "10.0.0.0/16"
subnet_cidr          = "10.0.1.0/24"
# IMPORTANT: restrict to your IP
allowed_ssh_cidr     = "<your-ip>/32"

# AMI configuration
ami_owner     = "099720109477" # Canonical
ami_name_filter     = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
ami_architecture     = "x86_64"

# Instance configuration
server_count         = 3   # Use odd numbers: 3, 5, or 7
client_count         = 2
ingress_client_count = 0   # Leave at 0 unless you're deploying Option E — see that section
server_instance_type = "t3.micro"
client_instance_type = "t3.medium"
```

### Step 2: Initialize Terraform

```bash
terraform init
```

This command downloads the AWS, Local, Null, and TLS providers.

### Step 3: Review the execution plan

```bash
terraform plan
```

Terraform creates approximately 18 resources. Review instance types, counts, and security group rules before proceeding.

### Step 4: Apply

```bash
terraform apply
```

Type `yes` when prompted. Terraform takes approximately five minutes to complete.

**What Terraform creates:**

| Resource | Details |
|----------|---------|
| VPC | `10.0.0.0/16`, DNS enabled |
| Public subnet | `10.0.1.0/24`, auto-assign public IPs |
| Internet gateway | Attached to VPC |
| Route table | Default route `0.0.0.0/0` → internet gateway |
| Security group | Static: 22 (SSH), 8500 (Consul HTTP, loopback only), 8443 (Consul HTTPS), 4646 (Nomad); configurable: `extra_ingress_ports` variable (default: 9002); all-internal |
| Server EC2 instances (×3) | Ubuntu 24.04, t3.medium, 50 GB gp3, tagged `AutoJoinRole=server` |
| Client EC2 instances (×2) | Ubuntu 24.04, t3.medium, 50 GB gp3, tagged `AutoJoinRole=client` |
| IAM instance profile | `ec2:DescribeInstances` for Cloud Auto-Join |
| SSH key pair | Written to `ansible/ssh_key.pem` (mode 0600) |
| Ansible inventory | Written to `ansible/inventory.ini` |

### Step 5: Review Terraform outputs

```bash
terraform output
terraform output nomad_ui_urls
terraform output ssh_commands
```

### Step 6: Verify SSH connectivity

Before you verify connectivity, make sure your AWS VM instances are running.

```bash
cd ../../ansible
ansible all -m ping
```

Expected output is `pong` from all five hosts. If connections fail:

```bash
chmod 600 ssh_key.pem
ansible all -m ping -vvv
```

---

## Phase 2: Cluster configuration (Ansible)

Run all commands from the `ansible/` directory with `-i inventory.ini`.

Six use case entrypoints cover the most common deployment scenarios. Each one
first runs `common_setup`, which tests Ansible connectivity and configures all
hosts. Then the process executes the required sub-playbooks in order and
finishes with a `cluster_summary` (or, for the Get Started option, a plain
completion banner) that prints ready-to-paste `export` commands. The Consul/
Nomad options (A-E) enable ACLs and create bootstrap tokens; the Get Started
option disables ACLs and TLS entirely.

Choose the option that matches your requirements.

---

### Option Get Started: single-node Nomad agent — `deploy_get_started.yaml`

Deploys a single combined Nomad server+client node with no Consul, no TLS,
and no ACLs — equivalent to `nomad agent -dev`. Use this for the
[Get Started tutorials](https://developer.hashicorp.com/nomad/tutorials/get-started),
which expect a zero-config single node rather than an HA cluster.

Requires `server_count = 1` and `client_count = 0` in
[`terraform/aws/terraform.tfvars`](terraform/aws/terraform.tfvars) — re-run
`terraform apply` after changing these before running this playbook.

```bash
ansible-playbook -i inventory.ini deploy_get_started.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1 | `common_setup` | `all` | Configures passwordless sudo; tests Ansible connectivity (ping) |
| 2 | `get_started` | `[servers]` (the single node) | Installs Docker; installs Nomad 2.0.4 with `nomad_server_enabled: true` **and** `nomad_client_enabled: true` on the same node, `bootstrap_expect: 1`, TLS and ACLs disabled; waits for port 4646 |
| 3 | completion banner | `localhost` | Prints SSH access, the plain-HTTP Nomad UI URL, and an `export NOMAD_ADDR=http://...` command |

**Duration:** ~5 minutes (single node, no TLS cert generation, no ACL bootstrap)

This scenario does not create any token files in `ansible/tokens/`, and
`set-cluster-env.sh` does not apply since there is no Consul/Nomad ACL token
to export — set `NOMAD_ADDR` manually as printed by the completion banner.

---

### Option A: Consul cluster only — `deploy_consul.yaml`

Deploys Consul servers and clients, bootstraps Consul ACL, and configures
dnsmasq for `.global` DNS forwarding on all nodes. Use this when you need only
Consul for service discovery or service mesh without Nomad.

Set Consul version and other variables in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_consul.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1 | `common_setup` | `all` | Configures passwordless sudo; tests Ansible connectivity (ping) |
| 2 | `consul_servers` | `[servers]` | Installs Consul 2.0.2 in server mode; enables Cloud Auto-Join using the `AutoJoinRole=server` EC2 tag; generates self-signed TLS certificates (TLS enabled by default); writes `/etc/consul.d/consul.hcl`; starts service; waits for the loopback HTTP port 8500 |
| 3 | `consul_clients` | `[clients]` | Installs Consul 2.0.2 in client mode; joins the server cluster through Cloud Auto-Join |
| 4 | `consul_acl_bootstrap` | `servers[0]` | Bootstraps Consul ACL; saves management token to `ansible/tokens/consul-bootstrap-*.txt` |
| 5 | `consul_dns_token` | `servers[0]` + `[clients]` | Creates `dns-access` ACL policy; creates a shared DNS token and one per-node node-identity agent token per client; applies the DNS token to every Consul agent using `consul acl set-agent-token dns`; re-runs consul role on each client with `consul_acl_enabled: true` to write `acl { tokens { agent dns } }` into `consul.hcl`; saves `ansible/tokens/consul-dns-secret-id.txt` and `ansible/tokens/consul-client-agent-<hostname>-secret-id.txt` |
| 6 | `dnsmasq` | `all` | Installs dnsmasq; disables systemd-resolved stub listener; forwards `.global` queries to `127.0.0.1:8600`; binds to `172.17.0.1` as well so Docker containers can reach dnsmasq; rewrites `/etc/resolv.conf` |
| 7 | `consul_acl_deny_anonymous` | `servers[0]` | Attaches a deny-all policy to the Consul anonymous token; unauthenticated API and DNS requests are rejected after this step |
| 8 | `cluster_summary` | `localhost` | Prints Consul bootstrap token, `export CONSUL_HTTP_ADDR` and `export CONSUL_HTTP_TOKEN` commands, and Consul UI URL |

Duration: approximately 10 minutes.

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting).

To remove what Ansible deployed, run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to remove the environment variables from your terminal.

---

### Option B: Nomad cluster only — `deploy_nomad.yaml`

Deploys Nomad servers and clients and bootstraps Nomad ACL. No Consul integration. Use this when you need only Nomad for workload orchestration.

Set Nomad and CNI plugin versions in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_nomad.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1 | `common_setup` | `all` | Configures passwordless sudo; tests Ansible connectivity (ping) |
| 2 | `nomad_servers` | `[servers]` | Installs Nomad 2.0.4 in server mode; uses static `server_join.retry_join` with private IPs from the `[servers]` group; generates self-signed TLS certificates (TLS enabled by default); writes `/etc/nomad.d/nomad.hcl`; starts service; waits for HTTPS port 4646 |
| 3 | `nomad_clients` | `[clients]` | Installs Nomad 2.0.4 in client mode; installs CNI plugins (Ubuntu) and Docker CE; uses static `server_join.retry_join` |
| 4 | `nomad_acl_bootstrap` | `servers[0]` | Bootstraps Nomad ACL; saves management token to `ansible/tokens/nomad-bootstrap-*.txt` |
| 5 | `cluster_summary` | `localhost` | Prints Nomad bootstrap token, `export NOMAD_ADDR` and `export NOMAD_TOKEN` commands, and Nomad UI URL |

Duration: approximately 10 minutes.

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting).

To remove what Ansible deployed, run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to remove the environment variables from your terminal.

---

### Option C: Consul + Nomad with service discovery — `deploy_consul_nomad_sd.yaml`

Deploys a full Consul cluster and a full Nomad cluster, then creates Consul ACL
policies and scoped agent tokens for Nomad server and client agents.
Reconfigures all Nomad agents with a `consul { address token }` block so Nomad
uses Consul for service registration and health checks.

Set Consul, Nomad, and CNI plugin versions in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1 | `common_setup` | `all` | Configures passwordless sudo; tests Ansible connectivity (ping) |
| 2 | `consul_servers` | `[servers]` | Installs Consul 2.0.2 in server mode; enables Cloud Auto-Join |
| 3 | `consul_clients` | `[clients]` | Installs Consul 2.0.2 in client mode; joins server cluster |
| 4 | `consul_acl_bootstrap` | `servers[0]` | Bootstraps Consul ACL; saves management token to `ansible/tokens/` |
| 5 | `consul_dns_token` | `servers[0]` + `[clients]` | Creates `dns-access` ACL policy; creates DNS token and per-node node-identity agent tokens for each client; applies DNS token to all Consul agents; reconfigures Consul clients with ACL enabled and both tokens in `consul.hcl`; saves `ansible/tokens/consul-dns-secret-id.txt` and `ansible/tokens/consul-client-agent-<hostname>-secret-id.txt` |
| 6 | `dnsmasq` | `all` | Installs dnsmasq; configures `.global` DNS forwarding to port 8600; binds to both `127.0.0.1` and `172.17.0.1` |
| 7 | `consul_acl_deny_anonymous` | `servers[0]` | Attaches deny-all policy to the Consul anonymous token |
| 8 | `nomad_servers` | `[servers]` | Installs Nomad 2.0.4 in server mode; static `server_join.retry_join` |
| 9 | `nomad_clients` | `[clients]` | Installs Nomad 2.0.4 in client mode; installs CNI plugins and Docker CE |
| 10 | `nomad_acl_bootstrap` | `servers[0]` | Bootstraps Nomad ACL; saves management token to `ansible/tokens/` |
| 11 | `consul_nomad_service_discovery` | `servers[0]` + `all` | Creates Consul ACL policies `nomad-server-policy` and `nomad-client-policy`; creates scoped agent tokens for Nomad servers and clients; saves token SecretIDs to `ansible/tokens/nomad-consul-*-secret-id.txt`; reconfigures Nomad servers and clients with `consul { address token }` block; restarts Nomad on all nodes |
| 12 | `cluster_summary` | `localhost` | Prints all tokens, all `export` commands, and both UI URLs |

**Status summary includes:** Consul bootstrap token, Nomad bootstrap token, Consul agent token for Nomad servers, Consul agent token for Nomad clients, `export CONSUL_HTTP_ADDR`, `export CONSUL_HTTP_TOKEN`, `export NOMAD_ADDR`, `export NOMAD_TOKEN`, and both UI URLs.

Duration: approximately 15 minutes.

To add workload identity to this deployment later:

```bash
ansible-playbook -i inventory.ini playbooks/consul_nomad_workload_identity.yaml
```

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting).

To remove what Ansible deployed, run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to remove the environment variables from your terminal.

---

### Option D: Consul + Nomad with service discovery and workload identity — `deploy_consul_nomad_wi.yaml`

Extends Option C by configuring a Consul JWT auth method that validates Nomad workload JWTs, and adding `service_identity` and `task_identity` blocks to the Nomad server configuration. Nomad services and tasks automatically exchange a short-lived JWT for a scoped Consul ACL token at runtime. Job files require no static secrets.

Set Consul, Nomad, and CNI plugin versions in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1–11 | Same as Option C | — | Refer to Option C table |
| 12 | `consul_nomad_workload_identity` | `servers[0]` + `[servers]` | Creates Consul ACL policy `nomad-tasks-policy`; creates JWT auth method `nomad-workloads` (JWKS URL points to the first Nomad server's HTTPS port 4646, trusted via the shared self-signed CA); creates binding rule mapping `nomad_service` JWT claims to Consul service identities; creates role `nomad-tasks-default`; creates binding rule mapping task workload JWTs to `nomad-tasks-default`; reconfigures Nomad servers with `service_identity` and `task_identity` blocks in the `consul {}` stanza; restarts Nomad servers |
| 13 | `cluster_summary` | `localhost` | Prints all tokens, all `export` commands, and both UI URLs |

**Status summary includes:** same as Option C.

Duration: approximately 15 minutes.

Verify the JWT auth method after deployment:

```bash
consul acl auth-method list
# Expected output includes: nomad-workloads
```

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting).

To remove what Ansible deployed, run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to remove the environment variables from your terminal.

---

### Option E: Consul + Nomad with service discovery, workload identity, and service mesh — `deploy_consul_nomad_mesh.yaml`

**Requires `ingress_client_count = 1` in `terraform.tfvars`**, set *before*
running `terraform apply` in [Phase 1](#phase-1-provision-infrastructure-terraform) —
this provisions the dedicated public client the API Gateway runs on. It
defaults to `0` because Terraform provisioning is shared across every
Option in this guide and runs before you pick one; every Option other than
E should leave it at `0`. If you already provisioned without it, edit
`terraform.tfvars` and re-run `terraform apply` — it's additive (adds one
instance and one security group, doesn't touch existing servers/clients).

> **Multipass**: `ingress_client_count` also exists in
> `terraform/multipass/`, provisioning a client tagged
> `nomad_node_role=ingress` the same way — but since Multipass has no
> security-group equivalent, it only affects Nomad scheduling, not network
> access. Countdash works end-to-end there; HashiCups does not —
> `hashicorpdemoapp/payments` has no arm64 build and crash-loops with `exec
> format error` on Apple Silicon. See
> [`_context/wiki/dedicated-ingress-node-plan.md`](_context/wiki/dedicated-ingress-node-plan.md)'s
> addendum.

Extends Option D by enabling Consul service mesh cluster-wide:

- Consul servers and clients are reconfigured with `connect.enabled = true` and
a TLS-enabled gRPC port (`grpc_tls = 8503`).
- Nomad clients are reconfigured with `consul.grpc_address` /
`consul.grpc_ca_file` so Nomad can bootstrap Envoy sidecars against Consul's TLS
gRPC/xDS listener.
- A new Nomad `ingress` namespace and a Consul ACL binding rule for the built-in
`api-gateway` templated policy are created, reusing the `nomad-workloads` JWT
auth method from Option D — no new auth method.

Set Consul, Nomad, and CNI plugin versions in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_consul_nomad_mesh.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1–13 | Same as Option D | — | Refer to Option D table |
| 14 | `consul_nomad_service_mesh` | `[servers]` + `[clients]` | Re-renders `consul.hcl` on servers and clients with `connect.enabled = true` and `grpc_tls = 8503`; restarts Consul; re-renders `nomad.hcl` on Nomad clients with `consul.grpc_address` / `consul.grpc_ca_file`; restarts Nomad clients; creates the Nomad `ingress` namespace; creates the Consul ACL binding rule mapping the API Gateway's workload identity to the `builtin/api-gateway` templated policy |
| 15 | `cluster_summary` | `localhost` | Prints all tokens, all `export` commands, and both UI URLs |

**Status summary includes:** same as Option D.

Duration: approximately 15–20 minutes.

Verify Consul Connect is fingerprinted on every Nomad client after deployment:

```bash
nomad node status -verbose \
  $(nomad node status -short | grep ready | awk '{print $1}') \
  | grep consul.connect
# consul.connect = true   (must appear for every client node)
```

Also confirm the dedicated public ingress client (provisioned by Terraform
via `ingress_client_count`, see the variable table above) is tagged
correctly — the API Gateway job below is constrained to schedule only there:

```bash
nomad node status -verbose \
  $(nomad node status -short | grep ready | awk '{print $1}') \
  | grep nodeRole
# meta.nodeRole = ingress   (must appear for exactly one client node)
```

This playbook only configures the cluster infrastructure for service mesh. It
does **not** deploy any mesh-enabled application jobs, Consul config entries
(service-defaults, intentions, api-gateway listener), or the API Gateway
itself — those are an application-level concern applied separately. Follow
[nomad-jobs/consul-mesh/README.md](nomad-jobs/consul-mesh/README.md) for the
full deploy order (service-defaults → intentions → TLS cert → gateway
listener → http-route → mesh app job → API Gateway job), which deploys:

- [`nomad-jobs/consul-mesh/countdash-transparent-proxy.nomad.hcl`](nomad-jobs/consul-mesh/countdash-transparent-proxy.nomad.hcl) and/or
  [`nomad-jobs/consul-mesh/hashicups-consul-service-mesh.nomad.hcl`](nomad-jobs/consul-mesh/hashicups-consul-service-mesh.nomad.hcl) — the two demo apps, mesh-enabled with Envoy sidecars. Countdash defaults to Consul's `transparent_proxy` mode (see below); HashiCups still uses explicit `upstreams`.
- [`nomad-jobs/consul-mesh/api-gateway.nomad.hcl`](nomad-jobs/consul-mesh/api-gateway.nomad.hcl) — an Envoy-based Consul API Gateway in the `ingress` namespace with two listeners, one per demo app: `https-countdash` on port 8447 and `https-hashicups` on port 8448, so both apps are reachable simultaneously rather than sharing one path-based route. Constrained to always schedule on the dedicated public ingress client (`meta.nodeRole = "ingress"`) — the only client whose security group opens these ports — rather than any client, so the gateway's public address is fixed and known ahead of time. See [`_context/wiki/dedicated-ingress-node-plan.md`](_context/wiki/dedicated-ingress-node-plan.md).

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting) and
[_context/wiki/api-gateway-envoy-bootstrap-troubleshooting.md](_context/wiki/api-gateway-envoy-bootstrap-troubleshooting.md).

**Why transparent proxy is the default for Countdash (live-verified):**
Consul's `transparent_proxy` mode needs no app-side rewiring — countdash-web
calls Consul's real DNS name and Envoy intercepts the connection — instead
of an explicit `upstreams` block bound to a fixed loopback port. See
[_context/wiki/transparent-proxy-vs-upstreams.md](_context/wiki/transparent-proxy-vs-upstreams.md)
for the tradeoffs. `consul_nomad_service_mesh.yaml` (run above) already
installs the required `consul-cni` CNI plugin and applies the Nomad ACL
policy the API Gateway job needs, so no separate manual steps remain.
Full rollout, four real bugs found and fixed along the way (a Consul
DNS-ACL-token regression, the wrong DNS name convention for
transparent-proxy interception, and two stale-catalog-entry cleanups), and
verification details in
[_context/wiki/transparent-proxy-enablement-plan.md](_context/wiki/transparent-proxy-enablement-plan.md).

**Alternative: explicit `upstreams` variant.**
[`nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl`](nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl)
uses an explicit `upstreams` block instead — no `consul-cni` dependency,
every dependency spelled out in the job spec. Can run alongside the
transparent-proxy job (independent job IDs):

```bash
nomad job run nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl
```

To remove what Ansible deployed, first stop the mesh app and gateway jobs (see
the Clean up section of [nomad-jobs/consul-mesh/README.md](nomad-jobs/consul-mesh/README.md)),
then run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to
remove the environment variables from your terminal.

---

### Option F: Nomad + Vault with workload identity — `deploy_nomad_vault.yaml`

Deploys a standalone Nomad cluster (no Consul) alongside a self-hosted Vault
cluster (Raft integrated storage, TLS), then configures a Vault JWT auth
method that validates Nomad workload identity JWTs, plus a scoped Vault ACL
policy and role. Nomad tasks that declare a `vault {}` block automatically
exchange their workload identity JWT for a short-lived, scoped Vault token —
no static Vault token in job specs or Nomad agent configuration.

Set Nomad, CNI plugin, and Vault versions in
[`ansible/group_vars/all.yaml`](ansible/group_vars/all.yaml) before running:

```bash
ansible-playbook -i inventory.ini deploy_nomad_vault.yaml
```

Sub-playbooks executed in order:

| Step | Sub-playbook | Hosts | What it does |
|------|-------------|-------|--------------|
| 1 | `common_setup` | `all` | Configures passwordless sudo; tests Ansible connectivity (ping) |
| 2 | `nomad_servers` | `[servers]` | Installs Nomad 2.0.4 in server mode; generates self-signed TLS certificates |
| 3 | `nomad_clients` | `[clients]` | Installs Nomad 2.0.4 in client mode; installs CNI plugins and Docker CE |
| 4 | `nomad_acl_bootstrap` | `servers[0]` | Bootstraps Nomad ACL; saves management token to `ansible/tokens/` |
| 5 | `vault_servers` | `[servers]` | Installs Vault 1.20.1 with Raft integrated storage and TLS (reuses the shared cluster CA); initializes Vault with a single unseal key share (`-key-shares=1 -key-threshold=1`, tutorial simplification — do not reuse for production); unseals every server; saves root token and unseal key to `ansible/tokens/vault-*.txt` |
| 6 | `nomad_vault_integration` | `servers[0]` + `[servers]` + `[clients]` | Enables Vault JWT auth method `jwt-nomad` (JWKS URL points to the first Nomad server's HTTPS port 4646, trusted via the shared self-signed CA); creates ACL policy `nomad-workloads-policy` scoped to `secret/data/nomad/*`; creates JWT role `nomad-workloads`; enables a KV v2 secrets engine at `secret/`; reconfigures Nomad servers and clients with a top-level `vault { jwt_auth_backend_path; default_identity }` block; restarts Nomad |
| 7 | `cluster_summary` | `localhost` | Prints Nomad and Vault tokens, all `export` commands, and both UI URLs |

**Status summary includes:** Nomad bootstrap token, Vault root token and unseal key, `export NOMAD_ADDR`, `export NOMAD_TOKEN`, `export VAULT_ADDR`, `export VAULT_TOKEN`, and both UI URLs.

Duration: approximately 15 minutes.

Vault's API port (8200) is **not** open in the security group by default. To
reach the Vault UI or API from outside the VPC, add `8200` to
`extra_ingress_ports` in `terraform.tfvars` before running `terraform apply`,
or use an SSH tunnel:

```bash
ssh -o 'IdentitiesOnly=yes' -i ssh_key.pem -L 8200:localhost:8200 ubuntu@<server-ip>
```

Verify the JWT auth method and secrets engine after deployment:

```bash
vault auth list
# Expected output includes: jwt-nomad/

vault secrets list
# Expected output includes: secret/
```

**Gap vs. the official tutorial:** the "Integrate Nomad with Vault" tutorial
category on developer.hashicorp.com contains one tutorial, "Generate mTLS
certificates for Nomad using Vault", which uses Vault's PKI secrets engine and
consul-template to dynamically generate and rotate Nomad's own mTLS
certificates. This use case implements the more general "Nomad tasks fetch
secrets from Vault via workload identity" pattern instead, which is not
reproduced by that specific tutorial but is a common, broadly useful
Nomad+Vault integration. See
[_context/wiki/nomad-tutorial-scenario-mapping.md](_context/wiki/nomad-tutorial-scenario-mapping.md).

If the process encounters issues, refer to the [Troubleshooting section](#troubleshooting).

To remove what Ansible deployed, run the `teardown.yaml` playbook. Then run `unset-cluster-env.sh` to remove the environment variables from your terminal.

---

## Post-deployment: set environment variables

After any deployment, source the helper script to export all environment variables automatically:

```bash
cd ansible
source ./set-cluster-env.sh
```

The script reads the first server IP from `inventory.ini` and token values from
`ansible/tokens/`. It only exports variables whose token files exist, so it
works correctly for all five Consul/Nomad options (A-E).

It also detects whether `inventory.ini` was generated for AWS or Multipass
and exports `NOMAD_VAR_deployment_platform` accordingly (`aws` or
`generic`). Some job specs (both Countdash service-discovery variants,
HashiCups' `nginx` group) use this to automatically register the correct
externally-reachable address in Consul/Nomad's service catalog — see
[Deploy a Nomad job](#deploy-a-nomad-job) below and
[`_context/wiki/deployment-platform-auto-detection.md`](_context/wiki/deployment-platform-auto-detection.md)
for the full mechanism. Always source this script before running
`nomad job run` on those job specs, on either platform.

> **Get Started option:** `set-cluster-env.sh` exports nothing for this
> scenario since it has no ACL bootstrap token. Use the `export
> NOMAD_ADDR=http://...` command printed by `deploy_get_started.yaml`'s
> completion banner instead.

### Manual export (without the helper script)

```bash
export CONSUL_HTTP_ADDR=https://<server-ip>:8443
export CONSUL_HTTP_TOKEN=$(cat ansible/tokens/consul-bootstrap-secret-id.txt)
export CONSUL_CACERT=ansible/.tls/ca.pem
export NOMAD_ADDR=https://<server-ip>:4646
export NOMAD_TOKEN=$(cat ansible/tokens/nomad-bootstrap-secret-id.txt)
export NOMAD_CACERT=ansible/.tls/ca.pem
```

Substitute `<server-ip>` with a server's public IP address from `terraform output` or `inventory.ini`. TLS is enabled by default, so both APIs require HTTPS and the self-signed CA certificate (`ansible/.tls/ca.pem`) to verify.

---

## Post-deployment verification

After you have set your environment variables, run the verification commands from
your local terminal.

You can also SSH to a server to run the verification commands. If you choose
this option, you must export the environment tokens after you SSH into
the server.

```bash
ssh -o 'IdentitiesOnly=yes' -i ansible/ssh_key.pem ubuntu@<server-public-ip>
```

Then set the environment variables.

```bash
CONSUL_HTTP_TOKEN=<paste-value-from-consul-bootstrap-secret-id.txt>
NOMAD_TOKEN=<paste-value-from-nomad-bootstrap-secret-id.txt>
```

### Verify Consul

```bash
# Should show 3 servers + 2 clients
consul members

# Expected output:
# Node                        Address          Status  Type    Build   Protocol  DC   Partition  Segment
# nomad-consul-server-1  10.0.1.x:8301   alive   server  2.0.2   2         dc1  default    <all>
# nomad-consul-server-2  10.0.1.y:8301   alive   server  2.0.2   2         dc1  default    <all>
# nomad-consul-server-3  10.0.1.z:8301   alive   server  2.0.2   2         dc1  default    <all>
# nomad-consul-client-1  10.0.1.a:8301   alive   client  2.0.2   2         dc1  default    <default>
# nomad-consul-client-2  10.0.1.b:8301   alive   client  2.0.2   2         dc1  default    <default>

consul info | grep -E "server|leader|peers"
```

### Verify Nomad

```bash
# Check server quorum (one node should be Leader)
nomad server members

# Expected output:
# Name                           Address     Port  Status  Leader  Raft Version  Build  DC   Region
# nomad-consul-server-1.dc1  10.0.1.x    4648  alive   false   3             2.0.4  dc1  global
# nomad-consul-server-2.dc1  10.0.1.y    4648  alive   true    3             2.0.4  dc1  global
# nomad-consul-server-3.dc1  10.0.1.z    4648  alive   false   3             2.0.4  dc1  global

# Check registered client nodes
nomad node status
```

### Access the UIs

| Service | URL |
|---------|-----|
| Consul UI | `https://<server-public-ip>:8443/ui` |
| Nomad UI | `https://<server-public-ip>:4646` |

TLS is enabled by default. The `ansible/.tls/ca.pem` CA that signs the Consul and
Nomad certificates is self-signed and generated locally by the `tls` role — it is
not issued by a certificate authority trusted by your OS or browser. Every browser
therefore shows a certificate warning, but the wording and severity differ:

| Browser | Behavior | Why |
|---------|----------|-----|
| Firefox | Shows "Warning: Potential Security Risk Ahead". Click **Advanced** > **Accept the Risk and Continue** to proceed. | Firefox keeps its own certificate trust store (separate from the OS) and always offers a per-site exception for an untrusted issuer, so it reliably lets you continue. |
| Chrome / Brave (Chromium-based) | Shows "Your connection is not private". Click **Advanced** > **Proceed** to continue. | Chromium browsers validate against the OS trust store, so an unrecognized self-signed CA still triggers a warning, but it is click-through like Firefox's. |
| Safari | Shows "This Connection is Not Private". Click **visit this website** (may require confirming again) to continue. | Safari validates against the macOS Keychain and shows the standard untrusted-CA warning with an override. |

> **Note**: Versions of this cluster's certificates generated before the `tls`
> role set a Common Name (`common_name`) and `keyUsage`/`extendedKeyUsage`
> extensions on node certificates had an empty certificate Subject combined
> with a non-critical Subject Alternative Name extension — a violation of
> [RFC 5280 §4.2.1.6](https://www.rfc-editor.org/rfc/rfc5280#section-4.2.1.6).
> Chrome/Brave and Safari enforce that rule strictly and rejected those
> certificates outright (`ERR_SSL_PROTOCOL_ERROR` / "sent scrambled credentials",
> or a non-bypassable Safari block) instead of showing the normal click-through
> warning. If you still see this behavior, re-run the deploy playbook (or the
> `tls` role plus the cert-distribution `helper` role step) to regenerate
> RFC 5280-compliant certificates — the CSR content change is detected
> automatically and the certificates are re-signed in place.

**Recommendation**: use Firefox to access the Consul and Nomad UIs during
testing and development — it consistently allows you to accept the self-signed
CA and continue.

If you want to use Chrome, Brave, Safari, or another Chromium/OS-trust-store
browser without warnings, import `ansible/.tls/ca.pem` into your OS or browser
trust store as a trusted root CA:

**macOS**

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain ansible/.tls/ca.pem
```

**Linux (Debian/Ubuntu)**

```bash
sudo cp ansible/.tls/ca.pem /usr/local/share/ca-certificates/nomad-consul-ca.crt
sudo update-ca-certificates
```

**Linux (RHEL/Fedora)**

```bash
sudo cp ansible/.tls/ca.pem /etc/pki/ca-trust/source/anchors/nomad-consul-ca.crt
sudo update-ca-trust extract
```

**Windows (PowerShell, run as Administrator)**

```powershell
Import-Certificate -FilePath "ansible\.tls\ca.pem" -CertStoreLocation Cert:\LocalMachine\Root
```

Only do this on a machine you control, and remove the trusted CA entry when
you tear down the cluster, since the CA's private key remains on the Ansible
control host.

Use the bootstrap token values to log into the UIs. Find the values in these files:

- Consul: `ansible/tokens/consul-bootstrap-secret-id.txt`
- Nomad: `ansible/tokens/nomad-bootstrap-secret-id.txt`

## Deploy a Nomad job

The job specification files for the example Countdash app are located under
the root-level `nomad-jobs` directory, one subdirectory per service-discovery
mechanism: `nomad-jobs/nomad-sd/` (Nomad-native) and `nomad-jobs/consul-sd/`
(Consul). The app has a web UI that connects to an API on the server. Port
9002 (web UI) is included in the default `extra_ingress_ports` list in
`terraform.tfvars`. To add ports for your own applications, see
[Managing security group ports](#managing-security-group-ports).

Both variants automatically register the Countdash web UI's correct
externally-reachable address (EC2 public hostname on AWS, the bridged VM
address on Multipass) as long as you've sourced
[`ansible/set-cluster-env.sh`](#post-deployment-set-environment-variables)
first — no manual `-var` flag needed on either platform. See
[`_context/wiki/deployment-platform-auto-detection.md`](_context/wiki/deployment-platform-auto-detection.md)
for how this works.

### Deploy the app with Nomad for service discovery

This Countdash version uses Nomad for service discovery. For details on service
discovery, refer to the [Configure service discovery
documentation](https://developer.hashicorp.com/nomad/docs/job-declare/service-discovery).

Change to the `nomad-jobs/nomad-sd` directory and deploy the job.

```bash
nomad job run countdash-nomad-service-discovery.nomad.hcl
nomad job status countdash-nomad-sd
```

Find the Countdash web application's public IP and port.

```bash
nomad service info -json countdash-web
```

The `Address` field contains the public URL, and the `Port` field
contains the port. Access the Countdash web UI at `http://<Address>:<Port>`.

Purge the job with `nomad job stop --purge countdash-nomad-sd`.

### Deploy the app with Consul for service discovery

This Countdash version uses Consul for service discovery. Refer to the [Configure
service discovery
documentation](https://developer.hashicorp.com/nomad/docs/job-declare/service-discovery)
for more information.

Change to the `nomad-jobs/consul-sd` directory and deploy the job. The same
command works on both Multipass and AWS:

```bash
nomad job run countdash-consul-service-discovery.nomad.hcl
nomad job status countdash-consul-sd
```

Use the Consul API to find the Countdash public address. Before running the following command, complete these steps:

- Set the [post-deployment environment variables](#post-deployment-set-environment-variables)
- [curl v8.3.0 or later](https://curl.se/)
- [jq](https://jqlang.org/)

```bash
curl --cacert "$CONSUL_CACERT" --variable '%CONSUL_HTTP_ADDR' --variable '%CONSUL_HTTP_TOKEN' --expand-url "{{CONSUL_HTTP_ADDR}}/v1/catalog/service/countdash-web?passing" --expand-header "X-Consul-Token: {{CONSUL_HTTP_TOKEN}}"  | jq -r '.[] | "\(.ServiceAddress):\(.ServicePort)"'
```

TLS is enabled by default, so `curl` needs `--cacert` pointed at the self-signed CA
(`$CONSUL_CACERT`, exported by `set-cluster-env.sh`) to verify the Consul HTTPS API.

The result displays the public URL.

---

## Troubleshooting

### Role not found: geerlingguy.docker

**Symptom:**

```
[ERROR]: The role 'geerlingguy.docker' was not found in: ...
```

The `geerlingguy.docker` role is an external Galaxy role that you must install
before running any playbook because that role is not bundled with this repository.

**Fix:** Run `ansible-galaxy install` from the `ansible/` directory:

```bash
cd ansible
ansible-galaxy install -r requirements.yaml
```

This installs all roles and collections declared in `requirements.yaml`, including `geerlingguy.docker`, into `~/.ansible/roles/` where Ansible can find them. Re-run the failed playbook after the install completes.

### Ansible locale encoding error

**Symptom:** `ERROR: Ansible requires the locale encoding to be UTF-8; Detected ISO8859-1`

Ansible only requires that the locale encoding on the control machine be UTF-8. It does not require a specific language or region. This error appears when the locale is set to a non-UTF-8 charset — for example, `it_IT` (ISO-8859-1) instead of `it_IT.UTF-8`.

**Fix:** Keep your locale; add the `.UTF-8` charset suffix:

```bash
export LANG=it_IT.UTF-8
export LC_ALL=it_IT.UTF-8
```

Substitute your actual locale (`fr_FR`, `de_DE`, `en_GB`, and so on). To make this permanent, add the exports to your shell profile (`~/.bashrc`, `~/.zshrc`, or equivalent).

Verify the result:

```bash
locale
# LANG=it_IT.UTF-8
# LC_ALL=it_IT.UTF-8
```

### SSH connection failures

```bash
# Fix key permissions
chmod 600 ansible/ssh_key.pem

# Test manually
ssh -i ansible/ssh_key.pem ubuntu@<server-ip>

# Run Ansible with verbose output
ansible all -m ping -vvv -i ansible/inventory.ini
```

### Consul not forming a quorum

```bash
# View Consul logs on a server
sudo journalctl -u consul -n 100

# Verify the AutoJoinRole tag exists on instances
aws ec2 describe-instances \
  --filters "Name=tag:AutoJoinRole,Values=server" \
  --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Tags]' \
  --output table

# Verify the IAM instance profile is attached
aws ec2 describe-instances \
  --filters "Name=tag:AutoJoinRole,Values=server" \
  --query 'Reservations[*].Instances[*].[InstanceId,IamInstanceProfile.Arn]' \
  --output table
```

### Nomad servers not forming a quorum

```bash
# View Nomad logs on a server
sudo journalctl -u nomad -n 100

# Confirm retry_join addresses are reachable from one server to another
ping <other-server-private-ip>
```

### Nomad clients not connecting to servers

```bash
# View Nomad client logs
sudo journalctl -u nomad -n 100

# Verify security group allows all internal traffic (protocol -1, self)
# This is set by network.tf and should already be correct
```

### Service not starting after config change

```bash
sudo systemctl status consul
sudo systemctl status nomad

# Follow logs in real time
sudo journalctl -u consul -f
sudo journalctl -u nomad -f
```

### Inspect the rendered configuration files

All configuration templates write their output to the remote host before the
service starts. Use the `debug_config` tag to read those files back to your
terminal and confirm the rendered values match your expectations.

```bash
# Print rendered configs for all roles in a full deployment run
ansible-playbook -i inventory.ini ansible/deploy_consul_nomad_sd.yaml --tags debug_config -v

# Inspect individual layers
ansible-playbook -i inventory.ini ansible/playbooks/nomad_servers.yaml --tags debug_config -v
ansible-playbook -i inventory.ini ansible/playbooks/nomad_clients.yaml --tags debug_config -v
ansible-playbook -i inventory.ini ansible/playbooks/consul_servers.yaml --tags debug_config -v
ansible-playbook -i inventory.ini ansible/playbooks/consul_clients.yaml --tags debug_config -v
```

The `-v` flag activates the debug output. Without it, the slurp tasks still run
but output is suppressed. The `consul.hcl` print task is automatically
suppressed when gossip encryption is enabled to avoid leaking the gossip key.

### Consul DNS returns SERVFAIL — stale token file from a previous cluster

After deploying a new cluster, `.global` DNS queries return SERVFAIL even
though `consul.hcl` on the clients shows an `acl.tokens.dns` value. Running
`consul acl token list` shows no `dns-access` policy and the UUID in the
config does not match any token in the ACL system.

**Cause:** `ansible/tokens/consul-dns-secret-id.txt` is a leftover from a
previous cluster. The `consul_dns_token.yaml` idempotency sentinel sees the
file and skips token creation, so the old UUID is written into the new
`consul.hcl` — pointing at a token that was never created for this cluster.

**Fix:** Delete the stale sentinel file and re-run the playbook.

```bash
cd ansible
rm tokens/consul-dns-secret-id.txt
ansible-playbook -i inventory.ini playbooks/consul_dns_token.yaml
```

After it completes, restart the Nomad job:

```bash
nomad job stop countdash-consul-sd
nomad job run nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl
```

**Prevention:** Always run `teardown.yaml` before destroying infrastructure.
If you skip teardown and run `terraform destroy` directly, manually delete all
files under `ansible/tokens/` before the next deployment:

```bash
rm ansible/tokens/*.txt
```

### Terraform: duplicate key pair error

```bash
aws ec2 delete-key-pair --key-name nomad-consul-key
# Then re-run terraform apply
```

### Terraform: InsufficientInstanceCapacity

Try a different availability zone or instance type (for example, `t3a.medium`). Alternatively, wait a few minutes and retry.

---

## Managing security group ports

Two approaches are available for adding ingress ports to the cluster's security group. See [ansible/README-SECURITY-GROUP.md](ansible/README-SECURITY-GROUP.md) for full details on both approaches.

### Terraform (persistent — survives terraform apply)

Edit `extra_ingress_ports` in `terraform/aws/terraform.tfvars`:

```hcl
extra_ingress_ports = [
  { port = 9002, description = "Countdash example app - web UI" },
  { port = 8080, description = "My application" },
]
```

```bash
cd terraform/aws
terraform plan
terraform apply
```

To close a port, remove its entry and re-apply. Terraform reconciles the security group against the list on every apply.

### Ansible (live cluster — no terraform apply required)

Use `update-security-group.yaml` to add a port to a running cluster immediately:

```bash
cd ansible
ansible-playbook update-security-group.yaml \
  -e custom_port=8080 \
  -e custom_port_description="My application"
```

The playbook is non-destructive (`purge_rules: false`) and checks for duplicate rules before adding. Ports added this way are **not tracked in Terraform state** and are absent when you run `terraform apply` with a list that does not include them.

---

## Advanced: run individual layers

Run individual sub-playbooks directly for targeted operations, such as re-deploying only the Consul servers or re-running ACL bootstrap after a reset.

> **Before running any sub-playbook**, install Galaxy roles if you have not already done so:
>
> ```bash
> cd ansible
> ansible-galaxy install -r requirements.yaml
> ```

### Consul layer

```bash
ansible-playbook -i inventory.ini playbooks/consul_servers.yaml
ansible-playbook -i inventory.ini playbooks/consul_clients.yaml
ansible-playbook -i inventory.ini playbooks/consul_acl_bootstrap.yaml
ansible-playbook -i inventory.ini playbooks/dnsmasq.yaml
```

Roles applied by `consul_servers` (in order):

| Role | Purpose |
|------|---------|
| `common` | Sets hostname, installs base packages |
| `geerlingguy.docker` | Installs Docker CE; adds `ubuntu` user to the docker group |
| `helper` | Installs apt packages: jq, net-tools, unzip, nano, curl |
| `tls` | Generates self-signed TLS certificates on the control machine (only when `consul_tls_enabled: true`) |
| `helper` | Copies TLS certs to `{{ consul_tls_dir }}` owned by the `consul` user (only when `consul_tls_enabled: true`) |
| `consul` | Installs Consul 2.0.2; writes `/etc/consul.d/consul.hcl`; creates systemd unit; starts service |

Key configuration values applied by `consul_servers`:

| Setting | Value |
|---------|-------|
| Mode | Server |
| `bootstrap_expect` | `{{ groups['servers'] \| length }}` |
| Datacenter | `dc1` |
| Cloud Auto-Join tag | `AutoJoinRole=server` |
| ACLs | Enabled |
| TLS | Enabled by default (set `consul_tls_enabled: false` to disable). Plain HTTP is kept on loopback (`127.0.0.1:8500`); HTTPS is exposed on `0.0.0.0:8443` |

Post-task: waits for Consul HTTP API on `127.0.0.1:8500`, then prints the HTTPS UI URL.

Roles applied by `consul_clients` (in order):

| Role | Purpose |
|------|---------|
| `common` | Sets hostname, installs base packages |
| `geerlingguy.docker` | Installs Docker CE; adds `ubuntu` user to the docker group |
| `helper` | Installs apt packages: jq, net-tools, unzip, nano, curl |
| `tls` | Generates self-signed TLS certificates on the control machine (only when `consul_tls_enabled: true`) |
| `helper` | Copies TLS certs to `{{ consul_tls_dir }}` owned by the `consul` user (only when `consul_tls_enabled: true`) |
| `consul` | Installs Consul 2.0.2 in client mode; Cloud Auto-Join finds servers using the `AutoJoinRole=server` tag |

Key configuration values applied by `consul_clients`:

| Setting | Value |
|---------|-------|
| Mode | Client |
| Cloud Auto-Join tag | `AutoJoinRole=server` |
| ACLs | Disabled on clients by default |
| TLS | Enabled by default (set `consul_tls_enabled: false` to disable) |

### Nomad layer

```bash
ansible-playbook -i inventory.ini playbooks/nomad_servers.yaml
ansible-playbook -i inventory.ini playbooks/nomad_clients.yaml
ansible-playbook -i inventory.ini playbooks/nomad_acl_bootstrap.yaml
```

Roles applied by `nomad_servers` (in order):

| Role | Purpose |
|------|---------|
| `common` | Sets hostname, installs base packages |
| `tls` | Generates self-signed TLS certificates on the control machine (only when `nomad_tls_enabled: true`) |
| `helper` | Installs build-essential, git, jq, net-tools, unzip, nano; copies TLS certs to `/etc/nomad.d/.tls/` when TLS is enabled |
| `nomad` | Installs Nomad 2.0.3; writes `/etc/nomad.d/nomad.hcl`; creates systemd unit; starts service |

Key configuration values applied by `nomad_servers`:

| Setting | Value |
|---------|-------|
| Mode | Server |
| `bootstrap_expect` | `{{ groups['servers'] \| length }}` |
| `server_join.retry_join` | Static list of server private IPs from `[servers]` inventory group |
| Cloud Auto-Join | Disabled (static join used instead) |
| ACLs | Enabled |
| TLS | Enabled by default (set `nomad_tls_enabled: false` to disable). Nomad has no loopback exception — HTTP and RPC are TLS-only |
| Log level | DEBUG |

Post-task: waits for Nomad HTTPS API on port 4646.

Roles applied by `nomad_clients` (in order):

| Role | Purpose |
|------|---------|
| `cni` | Installs CNI plugins (Ubuntu only) |
| `geerlingguy.docker` | Installs Docker CE |
| `tls` | Generates TLS certs (only when `nomad_tls_enabled: true`) |
| `helper` | Installs packages; loads `bridge` kernel module; copies TLS certs |
| `nomad` | Installs Nomad 2.0.3 in client mode |

Key configuration values applied by `nomad_clients`:

| Setting | Value |
|---------|-------|
| Mode | Client |
| `server_join.retry_join` | Static list of server private IPs from `[servers]` inventory group |
| Cloud Auto-Join | Disabled |
| ACLs | Enabled |
| TLS | Enabled by default (set `nomad_tls_enabled: false` to disable) |
| Log level | DEBUG |

Post-task: waits for Nomad HTTPS API on port 4646.

---


## ACL bootstrap (for individual layer deployments)

> [!IMPORTANT]
> ACL bootstrap is included automatically in all four use case
> entrypoints (`deploy_consul.yaml`, `deploy_nomad.yaml`,
> `deploy_consul_nomad_sd.yaml`, `deploy_consul_nomad_wi.yaml`). Only run these
> playbooks separately if you deployed Consul or Nomad using individual layer
> playbooks from the [Advanced section](#advanced-run-individual-layers).

Run the bootstrap once, after the cluster is first formed.

### Consul ACL bootstrap

```bash
ansible-playbook -i inventory.ini playbooks/consul_acl_bootstrap.yaml
```

Targets `servers[0]` (first server only). Calls `consul acl bootstrap`, saves the management token locally (mode 0600), and exits cleanly on re-runs.

**Output files** (on the Ansible control machine):

| File | Contents |
|------|----------|
| `ansible/tokens/consul-bootstrap-token-output.txt` | Full bootstrap output + usage notes |
| `ansible/tokens/consul-bootstrap-secret-id.txt` | SecretID only, for scripting |

**Use the token:**

```bash
export CONSUL_HTTP_TOKEN=$(cat ansible/tokens/consul-bootstrap-secret-id.txt)
consul members
consul acl token read -self
```

### Nomad ACL bootstrap

```bash
ansible-playbook -i inventory.ini playbooks/nomad_acl_bootstrap.yaml
```

Targets `servers[0]`. Calls `nomad acl bootstrap`, saves the management token locally (mode 0600), and exits cleanly on re-runs.

**Output files** (on the Ansible control machine):

| File | Contents |
|------|----------|
| `ansible/tokens/nomad-bootstrap-token-output.txt` | Full bootstrap output + usage notes |
| `ansible/tokens/nomad-bootstrap-secret-id.txt` | SecretID only, for scripting |

**Use the token:**

```bash
export NOMAD_TOKEN=$(cat ansible/tokens/nomad-bootstrap-secret-id.txt)
nomad server members
nomad acl token self
```

---

## Optional: external Application Load Balancer

For the [Load Balancer Integrations tutorial](https://developer.hashicorp.com/nomad/tutorials/load-balancing),
`terraform/aws/loadbalancer.tf` can provision an internet-facing ALB in front
of the Nomad clients. It's disabled by default and works with any deployed
use case (Get Started, A-E) — the ALB simply forwards HTTP traffic to a fixed
port on every client.

Edit `terraform/aws/terraform.tfvars`:

```hcl
enable_load_balancer      = true
load_balancer_target_port = 9002  # defaults to the Countdash demo app's web UI port
```

```bash
cd terraform/aws
terraform plan
terraform apply
terraform output load_balancer_url
```

This creates a second, instance-free subnet in a second Availability Zone (ALBs
require two AZs), a dedicated security group, a target group with one
attachment per client instance, and a port-80 listener. See
[_context/wiki/nomad-tutorials-infrastructure-roadmap.md](_context/wiki/nomad-tutorials-infrastructure-roadmap.md#phase-4--load-balancer-integration-implemented)
for what this does and does not reproduce from the tutorial.

To remove the ALB, set `enable_load_balancer = false` and re-apply.

---

## Optional: Nomad/Consul Enterprise licensing

For the [Nomad Enterprise tutorials](https://developer.hashicorp.com/nomad/tutorials/enterprise),
this repo can install Nomad/Consul Enterprise (`+ent`) binaries and load a
license instead of the open-source (CE) binaries. It's disabled by default
(`nomad_edition`/`consul_edition: "oss"`) and works with any deployed use
case that runs the `nomad`/`consul` roles (Get Started, A-F) — the toggle
lives in `ansible/group_vars/all.yaml`, not a dedicated deployment option.

You need valid Consul and Nomad Enterprise license files (`.hclic`). Place
them at:

```text
ansible/licenses/nomad.hclic    # required on Nomad servers only
ansible/licenses/consul.hclic   # required on all Consul agents (servers and clients)
```

This directory is gitignored — license files are never committed. Then edit
`ansible/group_vars/all.yaml`:

```yaml
nomad_edition: "enterprise"
consul_edition: "enterprise"
```

Run (or re-run) the playbooks for your chosen use case as normal. On the
first run against a given host, the `nomad`/`consul` roles download the
`+ent` release artifact instead of the CE one, and each server's
`license_path` config picks up the distributed license file.

Verify:

```bash
nomad version    # should show a "+ent" suffix
nomad license get

consul version   # should show a "+ent" suffix
consul license get
```

To revert to CE, set both vars back to `"oss"` and re-run — the role
re-downloads the CE binary since the pinned version string no longer
matches what's installed. See
[_context/wiki/enterprise-licensing-plan.md](_context/wiki/enterprise-licensing-plan.md)
for the full design and verification writeup.

---

## Cleanup

From the `ansible` directory, run the teardown playbook. The playbook removes software, reverses configuration on the VMs, and removes tokens and TLS certificates from your workstation.

```bash
ansible-playbook -i inventory.ini teardown.yaml
```

Then destroy all EC2 instances, VPC, IAM roles, and SSH key pairs.

```bash
cd ../terraform/aws
terraform destroy
```
