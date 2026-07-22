# Nomad Tutorial → Deploy Scenario Mapping

Phase 2 of [nomad-tutorials-infrastructure-roadmap.md](nomad-tutorials-infrastructure-roadmap.md).
Maps each tutorial in the Cluster Setup, Nomad Variables, Service Discovery,
Consul Integration, Edge Workloads, Vault Integration, and Load Balancer
Integrations categories on
[developer.hashicorp.com/nomad/tutorials](https://developer.hashicorp.com/nomad/tutorials)
to the existing `deploy_*.yaml` scenario (and, for Load Balancer Integrations,
the optional Terraform add-on) in this repo that satisfies its prerequisites.
This is a reference table only; the Load Balancer Integrations row (Phase 4)
and the Vault Integration row (Phase 3) are the exceptions where new code was
involved.

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

## Known gaps surfaced by this mapping

1. **GCP and Azure Cluster Setup tutorials** — not applicable; this repo is AWS-only (`terraform/aws/`). Out of scope unless a new cloud workspace is added.
2. **Multi-datacenter path-based ALB routing** — the Load Balancer Integrations tutorial's dc1/dc2 api/payments split and per-path listener rules are not reproduced by Phase 4's single target group. This repo has one datacenter per cluster; per-path routing is left as a follow-up Terraform exercise for users who want full tutorial parity.
3. **Vault PKI-based mTLS certificate generation and rotation for Nomad** — the sole tutorial in the Vault Integration category is not reproduced. Phase 3 implements a different, broadly useful Vault integration (secrets via workload identity) instead of Vault-managed dynamic Nomad certs.
