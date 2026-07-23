# nomad-infrastructure Knowledge Wiki

Index of durable knowledge for this project. Use this file to decide whether
to follow a link before acting. Do not read this file in full on every turn —
scan the headings and follow only what is relevant to the current task.

## Architecture and documentation

- [AGENTS.md](../../AGENTS.md) — canonical agent guide: architecture, key commands, conventions, security pitfalls, docs map
- [DEPLOY_CLUSTER_GUIDE.md](../../DEPLOY_CLUSTER_GUIDE.md) — full deployment walkthrough including Terraform + Ansible steps
- [ansible/PLAYBOOKS-README.md](../../ansible/PLAYBOOKS-README.md) — per-playbook reference including variables, tags, and rendered-config inspection
- [ansible/README.md](../../ansible/README.md) — Ansible role/variable overview and troubleshooting guide
- [tls-enabled-by-default-plan.md](tls-enabled-by-default-plan.md) — Plan and reasoning for enabling TLS by default in both Consul and Nomad across all deploy scenarios: hybrid Consul HTTP/HTTPS model, Nomad TLS-only (no loopback exception), shared self-signed CA, and the JWKS/CA-trust fix required for Consul-Nomad workload identity integration.
- [consul-service-mesh-plan.md](consul-service-mesh-plan.md) — **Proposal, not implemented.** Plan for a new Option E use case (`deploy_consul_nomad_mesh.yaml`) adding Consul service mesh (Connect) on top of Option D. Covers `consul_connect_enabled`/`grpc_tls` agent changes, the new Nomad `consul.grpc_ca_file`/`grpc_address` fields required for TLS-enabled Connect, the new `ingress` namespace + `builtin/api-gateway` binding rule (reusing the existing `nomad-workloads` auth method from workload identity), new (not modified) mesh job specs for Countdash and HashiCups, an explicit service-intentions allow-list, and a Consul API Gateway for external ingress.
- [enterprise-licensing-plan.md](enterprise-licensing-plan.md) — **Implemented and fully verified end-to-end on both Multipass and AWS (2026-07-22).** A cross-cutting `nomad_edition`/`consul_edition` toggle (`oss`/`enterprise`, default `oss`, set in `group_vars/all.yaml`) usable with any existing scenario. Installs the `+ent` release artifact (a version-string suffix — required zero changes to `hashicorp_release`) and distributes a license file from a new gitignored `ansible/licenses/` directory via the same `helper`-role pattern already used for TLS certs. Only Nomad *servers* need a license; every Consul agent (servers and clients) does. Deleted a dead, never-wired `license.hcl.j2` scaffold from the original Phase 6 planning pass. `nomad license get`/`consul license get` both confirmed valid (expiring 2027-08-21) on both platforms. Two operational gotchas hit and resolved along the way, both pre-existing/environmental, not code bugs: a wedged Multipass daemon needed a full reinstall, and the already-documented stale-Ansible-fact-cache-after-VM-recreate gotcha (see [multipass-local-testing-plan.md](multipass-local-testing-plan.md)) recurred and was fixed the same way (`rm -rf /tmp/ansible_facts`).
- [multipass-local-testing-plan.md](multipass-local-testing-plan.md) — **Phases 0-3 complete. Options D, E, F additionally live-verified 2026-07-22.** `terraform/multipass/` workspace (via the `larstobi/multipass` provider) applied against real VMs; `deploy_consul_nomad_sd.yaml` runs clean end to end. Most of the Ansible layer was already cloud-agnostic (arch auto-detection in `hashicorp_release`/`cni`, Nomad's static-IP `retry_join` fallback, generic TLS SANs, the `consul_use_aws_cloud_join` override for cloud auto-join). Documents a confirmed gotcha: Multipass VM IPs can drift (DHCP lease churn) between Ansible runs, and Ansible's `gathering = smart` + `fact_caching = jsonfile` can silently reuse stale cached facts even across the drift — `rm -rf /tmp/ansible_facts` (or `--flush-cache`) before re-running fixes it. Later additions: Option D verified with no code changes; Option E required fixing `consul_nomad_service_mesh.yaml`'s hardcoded AWS auto-join plus adding `ingress_client_count` to `terraform/multipass/` (see [dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md)'s addendum) — HashiCups remains unverifiable there due to an unrelated vendor arm64 image gap; Option F required fixing a Vault 1.20+ `disable_mlock` requirement (not Multipass-specific). Also documents a Multipass-daemon flakiness gotcha (VMs stuck in `Unknown` state after a rapid destroy→apply cycle — fixed via `multipass delete --all --purge`).
- [countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md) — Two Multipass-only bugs found in `countdash-consul-service-discovery.nomad.hcl`: (1) AWS-only `service.address` node attributes (`attr.unique.platform.aws.*`), same class of bug already fixed in `hashicups-multipass.nomad.hcl`, fixed the same way with `attr.unique.network.ip-address`; (2) `hashicorpdev/counter-api:v3`/`counter-dashboard:v3` are amd64-only (not multi-arch manifests) — fixed by interpolating `${attr.cpu.arch}` directly into `image` (empirically confirmed to work, since official docs don't clearly say so) to pick HashiCorp's published `v3-amd64`/`v3-arm64` tags per node. Verified with a live deploy.
- [countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md) — Extended both fixes above to `countdash-nomad-service-discovery.nomad.hcl` (both AWS-attribute + multi-arch) and `countdash-upstreams.nomad.hcl` (multi-arch only — no `service.address` field to fix there). Also found and fixed a real bug this surfaced: `countdash-consul-service-discovery.nomad.hcl` and `countdash-nomad-service-discovery.nomad.hcl` both declared `job "countdash"` — deploying one silently overwrote the other via an in-place Nomad job update, with no warning from `nomad job validate` since job-ID uniqueness is a runtime registry check, not a parse-time one. Renamed to `countdash-consul-sd` / `countdash-nomad-sd`; both now verified to coexist.
- [countdash-aws-public-address-fallback.md](countdash-aws-public-address-fallback.md) — Recovering `countdash-web`'s externally-reachable AWS address after the Multipass fix above traded it away. Two fixes: (1) new `terraform/aws/outputs.tf` outputs keyed by Nomad node name (`client_public_ips_by_node`) — no index cross-referencing needed; (2) a job variable to select `attr.unique.platform.aws.public-hostname` vs `attr.unique.network.ip-address`. **Important correction captured here**: initially assumed the unselected ternary branch was elided at parse time (seemingly confirmed by a misleading first test) — live-tested the `aws` branch on non-AWS infra and found this wrong: Nomad resolves `service.address` ternaries per-node at runtime, and silently registers the literal unresolved text (`${attr.unique.platform.aws.public-hostname}`) with no error when the attribute doesn't exist on that node, breaking the health check with a confusing `invalid URL escape` error rather than a clear cause. Superseded (not replaced) by [deployment-platform-auto-detection.md](deployment-platform-auto-detection.md) below, which automates supplying the variable's value.
- [deployment-platform-auto-detection.md](deployment-platform-auto-detection.md) — Removing the "forgot the `-var` flag" risk from the page above, expanded to every affected job spec (both countdash variants + HashiCups' `nginx` group). Tried the obvious "more automatic" fix first — Nomad node metadata (`meta.*`) as the ternary's condition, settable by Ansible with zero shell setup — and **live-testing proved it silently broken**: both `meta.*` and `attr.*` used as the ternary *condition* (as opposed to a *branch*) resolve to the wrong value with no error, even when confirmed true via a passing `constraint` block on the identical attribute as a control test. Only a `var.*` condition works. Pivoted to `NOMAD_VAR_deployment_platform`, wired into the existing `ansible/set-cluster-env.sh` (already sourced after every deploy) — detects AWS vs. Multipass from the same `consul_use_aws_cloud_join` signal Ansible already uses, no new files or Ansible role changes needed. Verified live across all three job specs with zero `-var` flags, real EC2 public hostnames registered automatically.
- [transparent-proxy-vs-upstreams.md](transparent-proxy-vs-upstreams.md) — Explains how explicit `upstreams` (used by this repo's mesh job specs) differs from Consul's `transparent_proxy` mode, why the mesh job specs couldn't use `transparent_proxy` at the time (the separate `consul-cni` CNI plugin wasn't installed — only the standard CNI bundle was), and confirms the mode choice is opt-in per task group, not a cluster-wide switch — so enabling `transparent_proxy` support would not break the existing `upstreams`-based jobs. See [transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md) for the actual implementation.
- [dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md) — **Implemented and verified end-to-end on AWS and Multipass** (Multipass added 2026-07-22 — see that page's addendum; HashiCups unverifiable there due to an unrelated vendor arm64 image gap, Countdash fully verified). Adds a dedicated public "ingress" Nomad client: a new `aws_instance.ingress_clients` Terraform resource with its own security group (only it opens the API Gateway's `8447` to `0.0.0.0/0`), a `nomad_node_role` inventory var threaded through to a Nomad client `meta { nodeRole = "ingress" }` stanza (sourced as an Ansible role default from the inventory fact, not a play `vars:`, to avoid the "forgot to re-supply on re-render" bug class), and a matching `constraint` block in `api-gateway.nomad.hcl` pinning the gateway there. No NAT Gateway / true private subnet — the other clients keep public IPs, just without app ports opened. Adapts a pattern confirmed live in the sibling `learn-consul-nomad-vm` repo. Scope is Option E (service mesh) only. Three bugs found and fixed during live rollout: `consul_nomad_api_gateway.yaml` was reopening 8447 on the shared security group and probing every client instead of just the ingress node; a pre-existing, unrelated idempotency bug in `consul_dns_token.yaml` (single-sentinel check) skipped per-node Consul agent token creation for the newly added client; and `ingress_client_count` originally defaulted to `1`, which — since Terraform provisioning is shared across every Option in `DEPLOY_CLUSTER_GUIDE.md` and runs before an Option is chosen — would have silently provisioned the extra instance for Get Started/Option A/B/C/F too (fixed by defaulting to `0` and requiring an explicit opt-in only in Option E's docs). Verified live: 3/3 gateway redeploys landed on the ingress node, and the security-group split was confirmed directly (8447 times out on internal clients, returns 200 on the ingress client). **Addendum:** the gateway now has two listeners instead of one — `https-countdash` (8447) and `https-hashicups` (8448) — so Countdash and HashiCups are reachable simultaneously in separate browser tabs, instead of sharing one path-based route where only the most-recently-applied one won. Chosen over `Hostnames`-based virtual hosting (would need a hosts-file entry per app) and path prefixes (Countdash/HashiCups both generate root-relative asset URLs with no base-path support, so subpath routing would likely break their assets). Re-surfaced the CLI-version-skew xDS bug (issue 6 in [api-gateway-envoy-bootstrap-troubleshooting.md](api-gateway-envoy-bootstrap-troubleshooting.md)) even with matching CLI versions — see that page's update for the fuller fix (delete+recreate config entries *and* full job stop+purge+redeploy, not either alone).
- [transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md) —
  **Implemented, made the default for Countdash, and fully live-verified
  (including automation of both former manual steps).** Adds the missing
  `consul-cni` CNI plugin (extends `ansible/roles/cni/`, wired into
  `consul_nomad_service_mesh.yaml` Play 2) and a new
  `countdash-transparent-proxy.nomad.hcl` job spec using `transparent_proxy {}`
  instead of `upstreams`. Four real bugs found in the initial rollout: (1) Nomad
  only fingerprints new CNI plugins at agent startup — automated via an Ansible
  `notify`/`handlers` restart, live-reverified with zero manual steps; (2)
  `consul_nomad_service_mesh.yaml` silently regressed the Consul DNS ACL token
  on restart, breaking all Consul DNS (fixed in the playbook); (3)
  transparent-proxy interception requires Consul's *virtual-IP* DNS name
  (`<service>.virtual.<domain>`), not the classic catalog DNS name — using the
  wrong one silently bypasses the mesh entirely; (4) stale Consul catalog
  entries from prior stopped allocs caused intermittent gateway 503s. A fifth
  bug (missing Nomad ACL policy for the gateway's Nomad Variable) was also
  automated into Play 4. `countdash-upstreams.nomad.hcl` remains available as
  the documented alternative (Step 7b); HashiCups is unaffected. See also issue
  6 in
  [api-gateway-envoy-bootstrap-troubleshooting.md](api-gateway-envoy-bootstrap-troubleshooting.md)
  for a local-CLI/server version-skew bug found during the final re-verification
  pass that produced the same 503 symptom as issue 4 there but with an unrelated
  root cause.

### Tutorials

- [nomad-tutorials-infrastructure-roadmap.md](nomad-tutorials-infrastructure-roadmap.md)
  — **Phases 1, 2, 3, 4, and 6 implemented; Phase 5 proposed; Phase 7 (new)
  planned but not implemented. All underlying deployment scenarios — Get Started
  and Options A–F in DEPLOY_CLUSTER_GUIDE.md — are implemented and
  live-verified.** Plan for using this repo's shared cluster to provision
  infrastructure for the different
  [developer.hashicorp.com/nomad/tutorials](https://developer.hashicorp.com/nomad/tutorials)
  categories: a single-node "Get Started" scenario (Phase 1, done —
  `deploy_get_started.yaml`), a tutorial-to-scenario mapping doc for categories
  already covered by existing scenarios (Phase 2, done), a self-hosted Vault
  cluster + Nomad workload identity secrets integration (Phase 3, done —
  `deploy_nomad_vault.yaml`, "Scenario F"), an optional Terraform ALB for Load
  Balancer Integration tutorials (Phase 4, done —
  `terraform/aws/loadbalancer.tf`), a second concurrent cluster for Federated
  Workload Identity (Phase 5, breaks the "one shared cluster" model by
  necessity), a cross-cutting Enterprise licensing toggle (Phase 6, done — see
  [enterprise-licensing-plan.md](enterprise-licensing-plan.md)), and the Nomad
  Autoscaler / Dynamic Application Sizing (Phase 7, planned, not started).
  Option E was further extended after these phases with a dedicated ingress
  client + dual-listener API Gateway — see
  [dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md).
- [nomad-tutorials-analysis.md](nomad-tutorials-analysis.md) —
  Tutorial-by-tutorial inventory (credited to IBM Bob) of every collection
  listed at
  [developer.hashicorp.com/nomad/tutorials](https://developer.hashicorp.com/nomad/tutorials):
  a quick-reference table plus a detailed entry per tutorial covering CE vs.
  Enterprise, ARM64 support, source repo, infrastructure targets, applications
  deployed, and Docker image architecture (Docker Hub/GHCR manifests checked
  live). Broader in scope than
  [nomad-tutorial-scenario-mapping.md](nomad-tutorial-scenario-mapping.md) below
  (which maps tutorials to this repo's own scenarios) — this doc is a standalone
  survey of the tutorials themselves, independent of this repo's implementation.
- [nomad-tutorial-scenario-mapping.md](nomad-tutorial-scenario-mapping.md) — Reference table mapping each tutorial in the Cluster Setup, Nomad Variables, Service Discovery, Consul Integration, Edge Workloads, Vault Integration, and Load Balancer Integrations categories to the `deploy_*.yaml` scenario (plus the optional ALB add-on) that satisfies it. Notes three gaps: GCP/Azure Cluster Setup tutorials don't apply to this AWS-only repo, the Load Balancer tutorial's multi-datacenter path-based routing isn't reproduced by the single target group this repo provisions, and the sole Vault Integration tutorial (Vault PKI-based mTLS cert rotation for Nomad) isn't reproduced — Phase 3 implements a different Vault integration (workload-identity-based secrets) instead. (Correction: an earlier version of this doc incorrectly claimed Nomad has a built-in, Consul-independent service mesh feature — it doesn't; the "Deploy an app with Nomad service discovery" tutorial's second half just uses the `nomadService` template function for static allocation pinning, already covered by Scenario B with no gap.)


## Dev-mode guides (macOS, standalone — not the Terraform/Ansible cluster)

- [devmode-macos-guide-review.md](devmode-macos-guide-review.md) — Accuracy review of [`devmode-macos/nomad.md`](../../devmode-macos/nomad.md) and [`devmode-macos/consul.md`](../../devmode-macos/consul.md) against the actual Nomad/Consul source (not just the docs site). Most dev-flag/port/TTL claims checked out exactly. Three bugs found and fixed: (1) §10's Consul command was missing `-domain=global`, so the Consul-SD Countdash job's hardcoded `countdash-api.service.dc1.global` DNS name (this repo's own domain convention, not a Consul default — see `ansible/group_vars/all.yaml`) could never resolve against a vanilla `-dev` agent, whose real default domain is `consul.`; (2) §9's `NOMAD_VAR_countdash_api_port` example silently no-ops because the job's variables are hyphenated and Nomad's env-var matching is an exact string comparison with no hyphen/underscore normalization, while shells can't export hyphenated names at all; (3) `consul.md`'s ports table mislabeled the vestigial, functionally-dead `proxy_min_port`/`proxy_max_port` range (`20000–20255`, from Consul's long-removed "managed proxy" feature) as an "Envoy xDS proxy range" — real xDS traffic uses the gRPC port (8502) already listed separately.

## ACL architecture

- [acl-architecture.md](acl-architecture.md) — Complete ACL reference for the cluster: every Consul and Nomad token that exists at runtime, its policy, which agent holds it, and which playbook creates it. Includes rendered `consul.hcl` and `nomad.hcl` ACL blocks, issuance dependency chain, workload identity JWT exchange flow, order-sensitivity rules, and a failure-mode quick-reference table.

## SSH / Ansible connectivity

- [ansible-ssh-too-many-auth-failures.md](ansible-ssh-too-many-auth-failures.md) — `ansible all -m ping` failing with `Too many authentication failures` against a freshly Terraform-applied AWS cluster, even with a correct key and inventory. Root cause: the user's own `~/.ssh/config` (`AddKeysToAgent yes`) silently accumulates a new key into the macOS ssh-agent on every successful connection using a freshly-generated `ssh_key.pem` — 6 stale keys from long-destroyed past clusters were still loaded — combined with `ansible.cfg` not setting `IdentitiesOnly=yes`, so every agent key got offered before the correct one, exceeding the remote sshd's `MaxAuthTries`. Fixed by adding `IdentitiesOnly=yes` to `ansible.cfg`'s `ssh_args`, matching what `terraform/aws/outputs.tf`'s manual SSH command output already did.

## dnsmasq and DNS

- [dnsmasq-consul-docker-dns.md](dnsmasq-consul-docker-dns.md) — How dnsmasq integrates with the OS (systemd-resolved, resolv.conf, config files), why it is required for Consul service discovery, and the Docker task driver DNS failure mode (`172.17.0.1` vs `127.0.0.1`) including the fix (`dnsmasq_listen_addresses` list, group_vars default).

## Troubleshooting

- [hashicups-https-ingress.md](hashicups-https-ingress.md) — Adding a self-signed HTTPS listener (port 443) to the HashiCups demo job's `nginx` group via a `prestart` cert-generation task, then removing the plain-HTTP listener (port 80) entirely so end users must use HTTPS. Covers the `/alloc` shared-directory pattern for passing a cert from an init task to the main task, the Consul health check `tls_skip_verify` requirement for self-signed certs, the AWS security group reconciliation via `terraform apply` (removes ad-hoc-added rules even though the Ansible `update-security-group.yaml` playbook only supports adding ports), and a **`NOMAD_IP_<label>` sanitization bug** (hyphens in port labels become underscores in the env var name, e.g. `nginx-tls` → `NOMAD_IP_nginx_tls`) that broke the first deploy attempt.
- [troubleshoot-consul-sd.md](troubleshoot-consul-sd.md) — "Counting service is unreachable" in the Countdash web UI when using Consul service discovery. Covers dnsmasq listen address verification, DNS resolution testing from inside the Docker container, cross-node TCP connectivity, Consul health check failure due to slow JVM startup, and **SERVFAIL caused by a stale DNS token file from a previous cluster** (Step 5 — the most common cause after a destroy-and-rebuild cycle).
- [nginx-upstream-dns-startup-failure.md](nginx-upstream-dns-startup-failure.md) — nginx `[emerg] host not found in upstream` crash loop when a multi-group Nomad job starts. Root cause: nginx resolves `upstream {}` hostnames at config-parse time, before upstream services register in Consul. Fix: `resolver 172.17.0.1 valid=5s` + `set $var` in `proxy_pass` to defer resolution to request time. Includes troubleshooting steps and caveat about loss of `upstream {}` load-balancing features.
- [consul-client-node-identity.md](consul-client-node-identity.md) — Why node identities are used (not a shared prefix policy) for Consul client agent tokens: least-privilege `node:write` scoping, no policy file to maintain, better audit trail. Covers the token-per-node file naming convention, idempotency sentinel, and the node-name-must-match constraint.
- [tls-enabled-troublshooting.md](tls-enabled-troublshooting.md) — Four linked TLS/mTLS bugs found in one session: (1) RFC 5280 violation (empty Subject + non-critical SAN) causing Chrome/Safari to hard-fail on the self-signed cert while Firefox only soft-warns; (2) a self-inflicted mTLS regression from an incomplete `serverAuth`-only Extended Key Usage list that broke Consul/Nomad server-to-server RPC entirely; (3) Consul failing to elect a Raft leader after redeploy because already-running Consul processes never reloaded newly-corrected certs (Go's `crypto/tls` does not hot-reload) — fixed reactively via manual restart and proactively via `notify`-wired restart handlers on all cert-copy tasks; (4) Nomad job placement failures (`${attr.consul.version}` constraint) caused by `consul_dns_token.yaml` Play 3 silently setting `consul_tls_enabled: false` on Consul clients, breaking client→server RPC with `rpc error making call: EOF` while servers still required mTLS. Includes the `openssl x509 -purpose` diagnostic pattern for catching EKU mTLS issues and log signatures for RPC-layer TLS mismatches.
- [api-gateway-envoy-bootstrap-troubleshooting.md](api-gateway-envoy-bootstrap-troubleshooting.md) — Six linked issues getting the Consul API Gateway (`nomad-jobs/consul-mesh/api-gateway.nomad.hcl`) genuinely working end-to-end: (1) `hashicorp/consul` images don't bundle `envoy`, and copying glibc `envoy` into the musl-based `consul` image fails with relocation errors — fixed by inverting the copy direction (static Go `consul` binary into the `envoyproxy/envoy` image via a prestart task); (2) the general musl-vs-glibc static/dynamic binary portability rule this implies; (3) `CONSUL_GRPC_ADDR` silently produces a plaintext xDS cluster against a TLS-only `grpc_tls` port unless given an explicit `https://` scheme, causing generic `connection_termination` errors — includes the `-bootstrap` flag diagnostic technique; (4) 503s from an otherwise-healthy gateway traced to **stale Consul catalog entries** for a stopped backend job's sidecar-proxy, surviving because the node's Consul agent's anti-entropy loop doesn't know to clean up entries it didn't itself register — fixed via `/v1/catalog/deregister` (not the agent-local endpoint); (5) rebuilding the gateway job from scratch fails with `Missing: nomad.var.block(...)` because zero Nomad ACL policies exist on the cluster and the task's implicit variable-access grant doesn't cover a path whose last segment differs from the task name — fixed with a workload-associated `nomad acl policy apply -job -group -task` policy, now automated in the mesh playbook's Play 4; (6) the **same 503 symptom as issue 4** but with a completely different root cause — a local `consul` CLI silently upgraded (by Homebrew) to a version newer than the cluster's actual servers, causing `consul config write` to encode config entries that desynced the API Gateway controller's generated route (RDS) and cluster (CDS) names — fixed by writing config entries via SSH using the server's own version-matched `consul` binary instead of the local one; **update:** recurred later even with matching CLI versions, so version skew is a trigger, not the sole cause — likely a genuine xDS staleness/race in Consul API Gateway v2's controller, reliably fixed only by deleting (not overwriting) the config entries *and* a full job stop+purge+redeploy together. Includes a `/dev/tcp` bash workaround for probing Envoy admin API in containers without curl/wget/nc.

## Established patterns

### Upgrade pattern (version bump)
1. Edit `ansible/group_vars/all.yaml` — single source of truth for version pins.
2. Run servers with `--serial 1` to preserve quorum: `ansible-playbook -i inventory.ini playbooks/nomad_servers.yaml --serial 1`
3. Run clients after: `ansible-playbook -i inventory.ini playbooks/nomad_clients.yaml`
4. Check `.github/plans/` for any existing upgrade plan before starting.

### Config validation before restart
Every HCL config template task must be followed by a validate task tagged
`nomad_validate` or `consul_validate` (e.g. `nomad validate /etc/nomad.d`).
This prevents service restarts on broken config.

### Rendered config inspection
All config-writing roles include `slurp` + `debug` tasks tagged `debug_config`.
Run with `-v` to print rendered files from the remote host:
```bash
ansible-playbook -i inventory.ini <playbook> --tags debug_config -v
```
`consul.hcl` output is automatically suppressed when gossip encryption is enabled.

### Consul token fallback (no workload identity)
For the service-discovery scenario (`deploy_consul_nomad_sd.yaml`), Nomad
clients use their own Consul ACL token for `template` blocks. This is
controlled by `nomad_client_use_consul_token: true`. The template block only
renders when `nomad_consul_integration_enabled=true` AND
`nomad_consul_workload_identity_enabled=false`.

**This var must be set in every play that re-renders `nomad.hcl` on the
clients, not just `nomad_clients.yaml`.** `consul_nomad_service_discovery.yaml`
Play 3 re-renders the client config later in the same scenario to inject the
real Consul token, and its own `vars:` block is independent — a play that
doesn't repeat `nomad_client_use_consul_token: true` silently falls back to
the role default (`false`), producing a client with a valid Consul token but
no `template { use_client_consul_token = true }` stanza, which breaks any job
using `{{ service "..." }}` in a `template` block with `403 (rpc error making
call: ACL not found)`. Hit and fixed 2026-07-20 — see
[acl-architecture.md §10](acl-architecture.md#10-common-acl-failure-modes).

## Upgrade plans

Stored in [.github/plans/](../../.github/plans/). Each plan documents impact
analysis, file changes, and rollout steps for a specific version upgrade.

| Plan | Versions |
|------|----------|
| [Update2.0.3-2.0.4.md](../../.github/plans/Update2.0.3-2.0.4.md) | Nomad 2.0.3 → 2.0.4 |
