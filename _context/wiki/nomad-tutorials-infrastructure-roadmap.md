# Roadmap: Using This Repo for Nomad Tutorial Infrastructure

**Status: Proposal. Phases 1, 2, 3, 4, and 6 implemented; Phase 5 not yet
implemented. Phase 7 (new, added 2026-07-22) planned but not implemented.**
**Underlying deployment scenarios: all of Get Started and Options A–F in
[DEPLOY_CLUSTER_GUIDE.md](../../DEPLOY_CLUSTER_GUIDE.md) are implemented and
live-verified** — Options A–D and the base of E predate this roadmap; Option F
(Vault) was added by Phase 3 below. Option E additionally gained a dedicated
public "ingress" Nomad client and a dual-listener API Gateway (Countdash on
`8447`, HashiCups on `8448`, reachable simultaneously) after this roadmap's
phases were written — see
[dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md). That work is
an Option E architecture improvement, not a new roadmap phase.

Goal: use this repo's Terraform + Ansible stack to stand up infrastructure for
the different use cases covered by the
[Nomad tutorials](https://developer.hashicorp.com/nomad/tutorials) on
developer.hashicorp.com, reusing one shared cluster (same Terraform state)
and reconfiguring it via playbooks/variables when switching between tutorial
categories, rather than maintaining a separate cluster per category.

## Tutorial category → scenario mapping

| Tutorial category | Tutorials | Infra approach |
|---|---|---|
| Get Started | 5 | **Phase 1** — new single-node scenario (`deploy_get_started.yaml`), no TLS/ACL/Consul, mirrors `nomad agent -dev` |
| Cluster Setup (Consul + ACLs) | 4 | **Phase 2** — already covered by existing Scenario C/D (`deploy_consul_nomad_sd.yaml` / `deploy_consul_nomad_wi.yaml`), no new code |
| Nomad Variables | 2 | **Phase 2** — works against any deployed cluster |
| Service Discovery | 2 | **Phase 2** — Scenario C |
| Consul Integration (health checks/mesh) | 4 | **Phase 2** — Scenario C/E (`deploy_consul_nomad_mesh.yaml`) |
| Edge Workloads | 1 | **Phase 2** — mostly a job-config concern, not infra; works against any existing scenario |
| Vault Integration | 1 | **Phase 3** — implemented: self-hosted Vault cluster + Nomad workload identity via `deploy_nomad_vault.yaml` ("Scenario F"). Implements the generic "Nomad tasks fetch secrets from Vault" pattern rather than the official tutorial's specific PKI/mTLS-cert-rotation scope (gap, see Phase 3 section below) |
| Load Balancer Integrations | 1 | **Phase 4** — implemented: optional ALB via `terraform/aws/loadbalancer.tf` (`enable_load_balancer = true`) |
| Federated Workload Identity | 1 | **Phase 5** — net-new, highest risk: requires a **second concurrent cluster** (breaks the "one shared cluster" model — federation is inherently cross-cluster) |
| Nomad Enterprise | 5 | **Phase 6** — implemented for the license-install + deploy-Enterprise-cluster tutorials (3 of 5); **Phase 7** covers the remaining 2 (Dynamic Application Sizing / Nomad Autoscaler), planned but not implemented |

## Phase 1 — "Get Started" single-node scenario (implemented)

The Get Started tutorials expect a `nomad agent -dev`-style single node, not
the HA topology. `server_count`, `client_count`, `nomad_tls_enabled`, and
`nomad_acl_enabled` were already parameterized in this repo, so no new
Terraform resources were needed.

- `terraform/aws/terraform.tfvars`: `server_count = 1`, `client_count = 0`.
- New sub-playbook `ansible/playbooks/get_started.yaml`: targets `hosts:
  servers`, sets `nomad_server_enabled: true` **and** `nomad_client_enabled:
  true` on the same node (combined server+client, like `-dev` mode),
  `nomad_server_bootstrap_expect: 1`, TLS and ACLs disabled, no Consul.
- New top-level entrypoint `ansible/deploy_get_started.yaml`: `common_setup`
  → `get_started` → `cluster_summary` (with a custom plain-`http://` UI
  banner, since the shared `cluster_summary.yaml` only prints `https://`
  URLs and this scenario has TLS disabled).

## Phase 2 — Tutorial mapping doc (implemented)

No new Terraform/Ansible code. Deliverable:
[nomad-tutorial-scenario-mapping.md](nomad-tutorial-scenario-mapping.md), a
table mapping each tutorial under Cluster Setup, Nomad Variables, Service
Discovery, Consul Integration, and Edge Workloads to the existing
`deploy_*.yaml` scenario that satisfies its prerequisites. Surfaced two
gaps: the GCP/Azure Cluster Setup tutorials aren't applicable to this
AWS-only repo, and Nomad's own built-in (Consul-independent) service mesh
(used in one Service Discovery tutorial) is a different feature from this
repo's Consul Connect-based Option E and isn't implemented here.

## Phase 3 — Vault integration (implemented)

HashiCorp's "Integrate Nomad with Vault" tutorial category on
developer.hashicorp.com contains exactly one tutorial, "Generate mTLS
certificates for Nomad using Vault", which uses Vault's PKI secrets engine
and consul-template to dynamically generate and rotate Nomad's own mTLS
certificates. That is a job/config-specific undertaking (consul-template
sidecar, PKI role and issuer setup, template stanzas for rotation), not the
generic infrastructure-provisioning concern this roadmap otherwise focuses
on. This phase instead implements the more general, broadly useful
"Nomad tasks fetch secrets from Vault via workload identity" pattern —
faithful to the roadmap's original Phase 3 intent — and documents the
PKI/mTLS tutorial as a **gap**, not reproduced here (see
[nomad-tutorial-scenario-mapping.md](nomad-tutorial-scenario-mapping.md)).

- New `ansible/roles/vault/` mirroring the `nomad`/`consul` role structure:
  `defaults/main.yaml`, `templates/vault.hcl.j2` (Raft integrated storage —
  no external storage backend or Consul dependency), `templates/vault.service.j2`,
  `meta/argument_specs.yaml`, `tasks/main.yaml` with a `vault_validate` tag
  (`vault operator diagnose`, `failed_when: false`) before the restart
  notify, `README.md`.
- New `ansible/roles/nomad_vault/` mirroring `nomad_consul`'s workload
  identity pattern: enables a Vault JWT auth method (`jwt-nomad`) trusting
  Nomad's JWKS endpoint, creates a read-only Vault ACL policy and JWT role
  scoped to Nomad task claims (`nomad_namespace`, `nomad_job_id`,
  `nomad_task`), and enables a KV v2 secrets engine at `secret/`.
- New sub-playbooks:
  - `ansible/playbooks/vault_servers.yaml` — installs Vault with Raft
    storage and TLS (reusing the shared cluster CA), initializes with a
    single unseal key share, unseals every server, saves the root token
    and unseal key to `ansible/tokens/`.
  - `ansible/playbooks/nomad_vault_integration.yaml` — three plays:
    bootstrap the Vault JWT auth method/policy/role, then re-render Nomad
    server config, then re-render Nomad client config, both with a
    top-level `vault { jwt_auth_backend_path; default_identity }` block.
- New top-level entrypoint `ansible/deploy_nomad_vault.yaml` ("Scenario F"),
  built on Nomad only (no Consul dependency — Vault integration does not
  require Consul): `common_setup` → `nomad_servers` → `nomad_clients` →
  `nomad_acl_bootstrap` → `vault_servers` → `nomad_vault_integration` →
  `cluster_summary`.
- Self-hosted Vault (new role), not HCP Vault, per project owner preference —
  keeps everything inside this repo's existing AWS EC2 model instead of
  adding an external managed-service dependency.
- Security simplifications (documented in `ansible/roles/vault/README.md`):
  single unseal key share (`-key-shares=1 -key-threshold=1` instead of
  Shamir's default 5-of-3, no auto-unseal/KMS) and running as `root`
  (matching this repo's existing Nomad/Consul convention) instead of a
  dedicated non-root user + `CAP_IPC_LOCK`. Neither pattern should be reused
  for a production Vault cluster.

## Phase 4 — Load Balancer Integration (implemented)

The Load Balancer Integrations tutorial's own example repo builds a
dedicated multi-datacenter cluster with an ALB in front of an internal
Nginx layer. Reproducing that exact api/payments/dc1/dc2 topology was out
of scope for a shared-cluster model, so this phase instead adds the generic
infrastructure piece — an ALB in front of the existing Nomad clients — which
is the part of the tutorial that is genuinely infra-specific. The rest of
the tutorial (internal load balancer job, path-based routing) is a job-spec
concern that works the same way against this ALB.

- New `terraform/aws/loadbalancer.tf`, gated by `enable_load_balancer`
  (default `false`):
  - `aws_lb` (internet-facing ALB) + `aws_lb_listener` on port 80.
  - `aws_lb_target_group` + one `aws_lb_target_group_attachment` per client
    instance, forwarding to `load_balancer_target_port` (default `9002`,
    the Countdash demo app's web UI port already opened via
    `extra_ingress_ports`).
  - `aws_security_group.alb_sg`, dedicated to the ALB (ingress 80 from
    `0.0.0.0/0`, egress restricted to the target port within the VPC CIDR).
  - `aws_subnet.alb_subnet`, a second, instance-free subnet in a second
    Availability Zone — ALBs require two AZs, but this repo's compute nodes
    live in a single subnet/AZ (see `network.tf`). This subnet carries no
    EC2 instances and doesn't change existing server/client placement.
- New variables: `enable_load_balancer` (bool), `load_balancer_target_port`
  (number, default `9002`), `alb_subnet_cidr` (string, default
  `10.0.2.0/24`).
- New outputs: `load_balancer_dns_name`, `load_balancer_url` (both `null`
  unless `enable_load_balancer = true`).
- No new Ansible role required — this is Terraform-only, and works with any
  already-deployed scenario (A-E) since the ALB simply forwards to whatever
  is listening on `load_balancer_target_port` on each client.
- Verified with `terraform validate` (`Success! The configuration is
  valid.`).
- Gap: multi-datacenter placement (dc1/dc2 constraints, per-service target
  groups, path-based `/api` vs `/payments` routing) from the tutorial's own
  example is **not** reproduced — this repo has one datacenter per cluster.
  A single target group covering all clients demonstrates the core ALB
  integration; per-path routing is left as a job-spec/Terraform exercise for
  users who want full tutorial parity.

## Phase 5 — Federated Workload Identity (not yet implemented)

- Requires a **second** Terraform state (e.g. `terraform/aws-secondary/`
  with its own `terraform.tfvars`, optionally a different region) to stand
  up a second Nomad/Consul cluster.
- New playbook to configure the federated ACL auth method on cluster B
  trusting cluster A's JWKS URL (extends the existing
  `consul_nomad_workload_identity.yaml` pattern cross-cluster).
- Recommended last: breaks the "one shared cluster" model and has the most
  moving parts of any phase.

## Phase 6 — Enterprise licensing (implemented)

The Nomad Enterprise tutorial category's 5 tutorials split into two
distinct pieces: license install + deploying an Enterprise cluster (3
tutorials, one of which — reference architecture — is a reading exercise
with no infra component), and Dynamic Application Sizing via the Nomad
Autoscaler (2 tutorials, deferred to **Phase 7** below). This phase covers
the former.

Unlike the original scaffolding plan (an unwired `nomad_edition` var and an
orphaned `ansible/roles/nomad/templates/license.hcl.j2` that was never
included by anything), this phase implements a fully wired, cross-cutting
toggle consistent with this roadmap's "one shared cluster, reconfigured via
playbooks/vars" lifecycle decision:

- `nomad_edition` / `consul_edition` (`oss`/`enterprise`, default `oss`) in
  `ansible/group_vars/all.yaml`, flowing into the `nomad` and `consul`
  roles' own matching defaults. `oss` is the default, so every existing
  scenario is unaffected unless a user opts in explicitly.
- Enterprise release artifacts are fetched by appending `+ent` to the
  pinned binary version (e.g. `2.0.4+ent`) before calling the
  `hashicorp_release` role — no changes were needed to that role at all;
  `releases.hashicorp.com`'s existing `{product}_{version}_{os}_{arch}.zip`
  URL scheme already handles `+ent` versions correctly.
- License files are distributed via the same `helper` role
  `helper_file_copy_local` pattern already used for TLS certs, from a new
  gitignored `ansible/licenses/` directory (`nomad.hclic`, `consul.hclic`)
  to `license_path` inside each product's rendered config — `server{}` for
  Nomad (servers only need a license), top-level for Consul (every agent,
  server and client, needs one).
- The dead `license.hcl.j2` scaffold was deleted; its content is now
  inlined into `nomad.hcl.j2`'s existing `{% if %}`-block style, matching
  every other conditional section in that template (TLS, telemetry, Consul,
  Vault).

Fully live-verified on both Multipass and AWS: `+ent` binaries install
correctly, the license file is distributed and loaded by both agents, and
`nomad license get`/`consul license get` both confirm a valid Enterprise
license on each platform — see
[enterprise-licensing-plan.md](enterprise-licensing-plan.md) for the full
design writeup and results.

## Phase 7 — Nomad Autoscaler / Dynamic Application Sizing (not yet implemented, planned)

Covers the remaining 2 of the 5 Nomad Enterprise tutorials: "Dynamic
Application Sizing concepts" and "Use Dynamic Application Sizing." Deferred
out of Phase 6's scope by explicit decision — this is materially bigger
than a license/edition toggle:

- Requires deploying the Nomad Autoscaler as its own binary/service (not
  part of the `nomad`/`consul` roles), likely a new
  `ansible/roles/nomad_autoscaler/` role mirroring the `vault` role's
  structure (systemd service, HCL config template, argument specs).
  Autoscaler releases follow the same `{product}_{version}_{os}_{arch}.zip`
  pattern as every other HashiCorp product on releases.hashicorp.com, so
  the existing `hashicorp_release` role should still apply unchanged.
- Requires an APM plugin (e.g. Prometheus) and a scaling policy attached to
  a job, plus a workload to actually generate the load the recommendations
  react to — closer to a job-spec/demo-app concern (like
  `nomad-jobs/consul-mesh/`) than a pure infra-provisioning one.
- Dynamic Application Sizing is Nomad Enterprise-only, so this phase has a
  hard dependency on Phase 6 already being enabled
  (`nomad_edition: enterprise`).
- Not started. Recorded here so the remaining 2/5 tutorial gap from Phase 6
  isn't lost.

## Decisions made

- **Lifecycle model:** one shared cluster, reconfigured via playbooks/vars —
  not a separate Terraform workspace per scenario, and not fully ephemeral
  per-tutorial provisioning. Exception: Phase 5 (Federated Workload
  Identity) inherently needs two concurrent clusters.
- **Scope:** all categories are in scope, including Load Balancer,
  Federated Workload Identity, and Enterprise (license install + Enterprise
  cluster deploy implemented in Phase 6; Nomad Autoscaler / Dynamic
  Application Sizing planned for Phase 7).
- **Vault:** new self-hosted Ansible role, not HCP Vault.
- **Get Started:** yes, add a dedicated lightweight single-node scenario
  rather than reusing the full HA cluster.
