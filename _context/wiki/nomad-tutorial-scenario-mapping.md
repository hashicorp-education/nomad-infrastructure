# Nomad Tutorial → Deploy Scenario Mapping

Phase 2 of [nomad-tutorials-infrastructure-roadmap.md](nomad-tutorials-infrastructure-roadmap.md).
Maps every tutorial across all 18 collections on
[developer.hashicorp.com/nomad/tutorials](https://developer.hashicorp.com/nomad/tutorials)
(Get Started, Job Specifications, AI Workloads, Autoscaler, Migrate a
Monolith, Advanced Scheduling, Cluster Setup, Edge Workloads, Enterprise,
Manage Clusters, Nomad Variables, Windows, Consul Integration, Load Balancer
Integrations, Service Discovery, Templates, Vault Integration, and Federated
Workload Identity) to the existing `deploy_*.yaml` scenario (and, for Load
Balancer Integrations, the optional Terraform add-on) in this repo that
satisfies its prerequisites. This is a reference table only; the Get Started
row (Phase 1), the Vault Integration row (Phase 3), the Load Balancer
Integrations row (Phase 4), and the Enterprise row (Phase 6) are the
exceptions where new code was involved. The Job Specifications and Templates
collections both list the same two Levant tutorials — HashiCorp cross-lists
them rather than duplicating content, and this doc follows suit.

Scenario letters refer to [DEPLOY_CLUSTER_GUIDE.md](../../DEPLOY_CLUSTER_GUIDE.md)
and the [deploy-scenario skill](../../.github/skills/deploy-scenario/SKILL.md):
**Get Started** (single-node), **A** (Consul only), **B** (Nomad only),
**C** (Consul + Nomad + service discovery), **D** (+ workload identity),
**E** (+ service mesh), **F** (Nomad + Vault workload identity, no Consul).

## Cluster Setup

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Nomad clusters on the cloud (overview) | [cluster-setup-overview](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-overview) | C or D | Conceptual overview; any Consul+Nomad+ACL scenario satisfies it |
| Set up a Nomad cluster on AWS | [cluster-setup-aws](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws) | **C** | Direct match — Consul + Nomad + ACLs on AWS. This repo also enables TLS by default (the tutorial does not), which is a superset, not a gap |
| Set up a Nomad cluster on GCP | [cluster-setup-gcp](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-gcp) | N/A | **Gap** — this repo only provisions AWS (`terraform/aws/`). Not applicable without a new `terraform/gcp/` workspace |
| Set up a Nomad cluster on Azure | [cluster-setup-azure](https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-azure) | N/A | **Gap** — same as GCP, AWS-only repo |

## Nomad Variables

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Create and update Nomad Variables | [variables-create](https://developer.hashicorp.com/nomad/tutorials/variables/variables-create) | **B** | Only needs a Nomad cluster; Consul not required |
| Configure access control for Nomad Variables | [variables-acls](https://developer.hashicorp.com/nomad/tutorials/variables/variables-acls) | **B** | Needs Nomad ACLs, which Scenario B already enables by default (`nomad_acl_enabled: true` in `nomad_servers.yaml`/`nomad_clients.yaml`) |

## Service Discovery on Nomad

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Deploy an app with Nomad service discovery | [service-discovery-app-deployment](https://developer.hashicorp.com/nomad/tutorials/service-discovery/service-discovery-app-deployment) | **B** | Direct match, full tutorial — Nomad has no built-in service mesh (only native service discovery); the tutorial's second half uses the `nomadService` template function to statically bind each upstream allocation to a specific downstream allocation, which Scenario B's plain Nomad-only cluster already supports with no additional infra |
| Convert from Nomad to Consul service discovery | [service-discovery-consul-conversion](https://developer.hashicorp.com/nomad/tutorials/service-discovery/service-discovery-consul-conversion) | **C** | Needs both Nomad native SD and Consul SD side by side to compare — exactly what Scenario C provides |

## Use Nomad's Consul Integration

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Configure Consul ACL with Nomad Workload Identities | [consul-acl](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-acl) | **D** | Direct match |
| Secure Nomad jobs with Consul service mesh | [consul-service-mesh](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-service-mesh) | **E** | Direct match — see `nomad-jobs/consul-mesh/README.md` for the app-level deploy steps this repo already automates |
| Consul service mesh in production | [service-mesh-production-checklist](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/service-mesh-production-checklist) | A or E | Conceptual best-practices checklist, not a hands-on lab; any Consul cluster works as a reference environment |
| Deploy a Consul API Gateway on Nomad | [deploy-api-gateway-on-nomad](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/deploy-api-gateway-on-nomad) | **E** | Direct match — this repo already has a working, automated implementation: `nomad-jobs/consul-mesh/api-gateway.nomad.hcl` + `ansible/playbooks/consul_nomad_api_gateway.yaml`. The gateway always schedules on a dedicated public ingress client (`ingress_client_count`, `meta.nodeRole` constraint) and exposes two listeners — `8447` (Countdash) and `8448` (HashiCups) — so both demo apps are reachable simultaneously; see [dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md) |

## Orchestrate Edge Services with Nomad

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Schedule edge Services with native service discovery | [schedule-edge-services](https://developer.hashicorp.com/nomad/tutorials/edge/schedule-edge-services) | **B** | Uses Nomad native SD and the `max_client_disconnect` job stanza to simulate unstable clients — a job-spec concern, not an infra concern; works against any scenario with Nomad clients. The tutorial's own Terraform/Packer provisioning can be skipped in favor of this repo's existing AWS infra |

## Load Balancer Integrations

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Manage external traffic with application load balancing | [external-application-load-balancing](https://developer.hashicorp.com/nomad/tutorials/load-balancing/external-application-load-balancing) | Any (**A**-**E**) + `enable_load_balancer = true` | **Partial match** — this repo's `terraform/aws/loadbalancer.tf` (Phase 4) provisions the ALB itself against any deployed scenario's clients. The tutorial's own dc1/dc2 api/payments split and path-based `/api` vs `/payments` routing rules are not reproduced — see the gap below |

## Integrate Nomad with Vault

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Generate mTLS certificates for Nomad using Vault | [vault-pki-nomad](https://developer.hashicorp.com/nomad/tutorials/integrate-vault/vault-pki-nomad) | N/A | **Gap** — this tutorial uses Vault's PKI secrets engine plus a consul-template sidecar to dynamically generate and rotate Nomad's own mTLS certificates. This repo's TLS instead uses a static, self-signed CA generated once by the `tls` role (see [tls-enabled-by-default-plan.md](tls-enabled-by-default-plan.md)); dynamic cert rotation via Vault PKI is not implemented |
| *(no official tutorial — implemented anyway)* | — | **F** | This repo implements the more general "Nomad tasks fetch secrets from Vault via workload identity" pattern instead (`deploy_nomad_vault.yaml`, Phase 3): a self-hosted Vault cluster (Raft storage, TLS) plus a Vault JWT auth method that trusts Nomad's workload identity tokens, letting `vault {}` blocks in job specs fetch scoped secrets with no static Vault token. Not a substitute for the PKI/mTLS tutorial above, but a common, broadly useful integration |

## Get Started

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Introduction to Nomad | [gs-overview](https://developer.hashicorp.com/nomad/tutorials/get-started/gs-overview) | N/A | Conceptual overview, no infra |
| Install the Nomad CLI | [gs-install](https://developer.hashicorp.com/nomad/tutorials/get-started/gs-install) | N/A | Local CLI install on the user's own machine; nothing to provision |
| Create a Nomad Cluster | [gs-start-a-cluster](https://developer.hashicorp.com/nomad/tutorials/get-started/gs-start-a-cluster) | **Get Started** | Direct match — Phase 1's `deploy_get_started.yaml` mirrors `nomad agent -dev` (combined server+client, no TLS/ACL/Consul) |
| Deploy and Update a Nomad Job | [gs-deploy-job](https://developer.hashicorp.com/nomad/tutorials/get-started/gs-deploy-job) | **Get Started** | Works against the same single-node cluster |
| Stop Nomad and Clean Up | [gs-stop-nomad](https://developer.hashicorp.com/nomad/tutorials/get-started/gs-stop-nomad) | Get Started | Teardown guidance; `terraform destroy` covers the same need |

## Job Specifications

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Create a parameterized Nomad job | [job-spec-parameterized](https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-parameterized) | **B** | Pure job-spec concern (dispatch jobs); works against any Nomad cluster |
| Migrate a Linux-based Java application to Nomad | [job-spec-java-linux](https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-java-linux) | N/A | **Gap** — needs a JDK/JRE installed on Nomad clients for the `java` task driver; no client role in this repo installs Java |
| Migrate a Windows-based Java application to Nomad | [job-spec-java-windows](https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-java-windows) | N/A | **Gap** — needs actual Windows Nomad clients, which this repo doesn't provision (see Windows collection below) |
| Template Nomad jobspecs with Levant | [dry-jobs-levant](https://developer.hashicorp.com/nomad/tutorials/job-specifications/dry-jobs-levant) | **B** | External Levant CLI run against any Nomad cluster; cross-listed under Templates |
| Template abstract job specs with Levant | [levant-abstract-jobs](https://developer.hashicorp.com/nomad/tutorials/job-specifications/levant-abstract-jobs) | **B** | Same as above; cross-listed under Templates |

## AI Workloads on Nomad

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| AI workloads on Nomad — Overview | [configure-ai-workload](https://developer.hashicorp.com/nomad/tutorials/ai-workloads/configure-ai-workload) | **B** | Configures a Granite/Ollama/Open WebUI job; works against any Nomad cluster with the Docker driver (already enabled by default) |
| Run a Granite AI workload on Nomad | [run-ai-workload](https://developer.hashicorp.com/nomad/tutorials/ai-workloads/run-ai-workload) | Partial | **Partial match** — the tutorial provisions its own dedicated AWS cluster via its own Terraform. This repo's Scenario B/C clients can run the job, but `terraform/aws/variables.tf` only offers general-purpose instance types (`t3.medium` default) — no GPU instance type is provisioned, so LLM inference would be CPU-only and unverified here |
| Scale node pools to run more AI models | [scale-ai-workload](https://developer.hashicorp.com/nomad/tutorials/ai-workloads/scale-ai-workload) | N/A | **Gap** — relies on Nomad node pools; no `node_pool` blocks exist anywhere in `ansible/roles/nomad/` |

## Autoscaler

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Scale an application with the Nomad Autoscaler | [autoscaler-vagrant-demo](https://developer.hashicorp.com/nomad/tutorials/autoscaler/autoscaler-vagrant-demo) | N/A | **Gap** — Phase 7 (Nomad Autoscaler) not yet implemented; this repo has no Autoscaler role/service |
| Scale your Nomad cluster with horizontal cluster autoscaling | [horizontal-cluster-scaling](https://developer.hashicorp.com/nomad/tutorials/autoscaler/horizontal-cluster-scaling) | N/A | **Gap** — same, and additionally needs an AWS ASG target plugin |
| Dynamically scale a Nomad cluster with the Nomad Autoscaler | [horizontal-cluster-scaling-on-demand-batch](https://developer.hashicorp.com/nomad/tutorials/autoscaler/horizontal-cluster-scaling-on-demand-batch) | N/A | **Gap** — same |
| Dynamic Application Sizing concepts | [dynamic-application-sizing-concepts](https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing-concepts) | N/A | **Gap** — Phase 7; cross-listed under Enterprise since DAS is an Enterprise-only feature |
| Use Dynamic Application Sizing | [dynamic-application-sizing](https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing) | N/A | **Gap** — Phase 7; cross-listed under Enterprise |

## Migrate a Monolith

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Migrate a monolith to microservices (overview) | [monolith-migration-overview](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-overview) | C or E | Conceptual overview |
| Set up the cluster with Consul and Nomad | [monolith-migration-cluster-setup](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-cluster-setup) | **C** | Direct match |
| Deploy HashiCups | [monolith-migration-hashicups](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-hashicups) | **C** | Direct match — this repo already has `nomad-jobs/consul-sd/hashicups.nomad.hcl` |
| Integrate service discovery | [monolith-migration-service-discovery](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-service-discovery) | **C** | Direct match — Consul SD on HashiCups already demoed in `nomad-jobs/consul-sd/README-hashicups.md` |
| Integrate service mesh and API gateway | [monolith-migration-service-mesh-gateway](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-service-mesh-gateway) | **E** | Direct match — `nomad-jobs/consul-mesh/hashicups-consul-service-mesh.nomad.hcl` + `api-gateway.nomad.hcl` (HashiCups on `8448`) already implement this exact scenario |
| Use the Nomad Autoscaler to scale a service | [monolith-migration-autoscale](https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-autoscale) | N/A | **Gap** — Phase 7 not implemented |

## Advanced Scheduling

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Oversubscribe memory | [memory-oversubscription](https://developer.hashicorp.com/nomad/tutorials/advanced-scheduling/memory-oversubscription) | **B** | Enabled at runtime via `nomad operator scheduler set-config`, a cluster-config/job-spec concern; works against any deployed Nomad cluster, no new infra needed |

## Nomad Enterprise

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Install a HashiCorp Enterprise license | [hashicorp-enterprise-license](https://developer.hashicorp.com/nomad/tutorials/enterprise/hashicorp-enterprise-license) | **B/C + `nomad_edition: enterprise`** | Direct match — Phase 6 |
| Discover Nomad reference architecture | [production-reference-architecture-vm-with-consul](https://developer.hashicorp.com/nomad/tutorials/enterprise/production-reference-architecture-vm-with-consul) | N/A | Reading exercise, no hands-on infra |
| Deploy a Nomad Enterprise cluster | [production-deployment-guide-vm-with-consul](https://developer.hashicorp.com/nomad/tutorials/enterprise/production-deployment-guide-vm-with-consul) | **C + `nomad_edition: enterprise`** | Direct match — Phase 6, live-verified on both Multipass and AWS |
| Dynamic Application Sizing concepts | [dynamic-application-sizing-concepts](https://developer.hashicorp.com/nomad/tutorials/enterprise/dynamic-application-sizing-concepts) | N/A | **Gap** — Phase 7 not implemented; cross-listed under Autoscaler |
| Use Dynamic Application Sizing | [dynamic-application-sizing](https://developer.hashicorp.com/nomad/tutorials/enterprise/dynamic-application-sizing) | N/A | **Gap** — Phase 7 not implemented, Vagrant-based; cross-listed under Autoscaler |

## Manage Clusters

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Use Prometheus to monitor Nomad metrics | [prometheus-metrics](https://developer.hashicorp.com/nomad/tutorials/manage-clusters/prometheus-metrics) | **B** | Direct match — `nomad_telemetry_enabled` / `nomad_telemetry_prometheus_metrics` are already wired into `ansible/roles/nomad/templates/nomad.hcl.j2` (both default `false`); flipping them satisfies the tutorial's Nomad-side setup. Deploying Prometheus itself is left as a job-spec exercise |
| Monitor job service metrics with Prometheus, Grafana, and Consul | [prometheus-service-mesh-metrics](https://developer.hashicorp.com/nomad/tutorials/manage-clusters/prometheus-service-mesh-metrics) | Partial | **Partial match** — Scenario E provides the Consul service mesh prerequisite (intentions, ingress); deploying Prometheus/Grafana as Nomad jobs and wiring service metrics isn't automated in this repo |

## Windows

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Run Nomad as a Windows service | [windows-agent](https://developer.hashicorp.com/nomad/tutorials/windows/windows-agent) | N/A | **Gap** — this repo provisions Linux EC2 instances only; no Windows AMI/Packer image or WinRM provisioning exists |

## Templates

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Template Nomad jobspecs with Levant | [dry-jobs-levant](https://developer.hashicorp.com/nomad/tutorials/templates/dry-jobs-levant) | **B** | Same tutorial as in Job Specifications above |
| Template abstract job specs with Levant | [levant-abstract-jobs](https://developer.hashicorp.com/nomad/tutorials/templates/levant-abstract-jobs) | **B** | Same tutorial as in Job Specifications above |

## Federated Workload Identity

| Tutorial | URL | Scenario | Notes |
|---|---|---|---|
| Federate access to GCP with Nomad Workload Identity | [integration-gcp](https://developer.hashicorp.com/nomad/tutorials/fed-workload-identity/integration-gcp) | N/A | **Gap** — Phase 5 (federated, multi-cluster) not implemented; also GCP-specific, and this repo is AWS-only |

## Known gaps surfaced by this mapping

1. **GCP and Azure Cluster Setup tutorials** — not applicable; this repo is AWS-only (`terraform/aws/`). Out of scope unless a new cloud workspace is added.
2. **Multi-datacenter path-based ALB routing** — the Load Balancer Integrations tutorial's dc1/dc2 api/payments split and per-path listener rules are not reproduced by Phase 4's single target group. This repo has one datacenter per cluster; per-path routing is left as a follow-up Terraform exercise for users who want full tutorial parity.
3. **Vault PKI-based mTLS certificate generation and rotation for Nomad** — the sole tutorial in the Vault Integration category is not reproduced. Phase 3 implements a different, broadly useful Vault integration (secrets via workload identity) instead of Vault-managed dynamic Nomad certs.
4. **Nomad Autoscaler (all 5 Autoscaler tutorials, plus the 2 Dynamic Application Sizing tutorials cross-listed under Enterprise, plus the Migrate a Monolith autoscale tutorial)** — Phase 7, not yet implemented. No `ansible/roles/nomad_autoscaler/` exists, so none of the 8 tutorials that depend on the Autoscaler binary/service are reproducible today.
5. **Java task driver tutorials (Linux and Windows)** — no client role in this repo installs a JDK/JRE, so the `java` task driver isn't usable out of the box.
6. **Windows Nomad clients** — this repo provisions Linux EC2 instances only; there's no Windows AMI/Packer image or WinRM provisioning, so the Windows collection's one tutorial and the Java-on-Windows tutorial are both unreachable.
7. **Nomad node pools** — no `node_pool` blocks exist in `ansible/roles/nomad/`, so the AI Workloads "scale node pools" tutorial isn't reproducible.
8. **Federated Workload Identity (GCP)** — Phase 5 (a second, federated Terraform cluster) is not implemented; the sole tutorial is also GCP-specific in an AWS-only repo, a double gap.
9. **GPU/LLM-sized instances for AI workloads** — `terraform/aws/variables.tf` only offers general-purpose instance types (`t3.medium` default client); the "Run a Granite AI workload" tutorial's own dedicated cluster is not reproduced or verified here.
10. **Prometheus/Grafana as deployed Nomad jobs** — this repo wires the Nomad-side telemetry config (`nomad_telemetry_enabled`, `prometheus_metrics`) but doesn't automate deploying Prometheus/Grafana themselves as jobs, so the service-mesh-metrics tutorial is only a partial match.
