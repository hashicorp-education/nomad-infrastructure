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

## ACL architecture

- [acl-architecture.md](acl-architecture.md) — Complete ACL reference for the cluster: every Consul and Nomad token that exists at runtime, its policy, which agent holds it, and which playbook creates it. Includes rendered `consul.hcl` and `nomad.hcl` ACL blocks, issuance dependency chain, workload identity JWT exchange flow, order-sensitivity rules, and a failure-mode quick-reference table.

## dnsmasq and DNS

- [dnsmasq-consul-docker-dns.md](dnsmasq-consul-docker-dns.md) — How dnsmasq integrates with the OS (systemd-resolved, resolv.conf, config files), why it is required for Consul service discovery, and the Docker task driver DNS failure mode (`172.17.0.1` vs `127.0.0.1`) including the fix (`dnsmasq_listen_addresses` list, group_vars default).

## Troubleshooting

- [hashicups-https-ingress.md](hashicups-https-ingress.md) — Adding a self-signed HTTPS listener (port 443) to the HashiCups demo job's `nginx` group via a `prestart` cert-generation task, then removing the plain-HTTP listener (port 80) entirely so end users must use HTTPS. Covers the `/alloc` shared-directory pattern for passing a cert from an init task to the main task, the Consul health check `tls_skip_verify` requirement for self-signed certs, the AWS security group reconciliation via `terraform apply` (removes ad-hoc-added rules even though the Ansible `update-security-group.yaml` playbook only supports adding ports), and a **`NOMAD_IP_<label>` sanitization bug** (hyphens in port labels become underscores in the env var name, e.g. `nginx-tls` → `NOMAD_IP_nginx_tls`) that broke the first deploy attempt.
- [troubleshoot-consul-sd.md](troubleshoot-consul-sd.md) — "Counting service is unreachable" in the Countdash web UI when using Consul service discovery. Covers dnsmasq listen address verification, DNS resolution testing from inside the Docker container, cross-node TCP connectivity, Consul health check failure due to slow JVM startup, and **SERVFAIL caused by a stale DNS token file from a previous cluster** (Step 5 — the most common cause after a destroy-and-rebuild cycle).
- [nginx-upstream-dns-startup-failure.md](nginx-upstream-dns-startup-failure.md) — nginx `[emerg] host not found in upstream` crash loop when a multi-group Nomad job starts. Root cause: nginx resolves `upstream {}` hostnames at config-parse time, before upstream services register in Consul. Fix: `resolver 172.17.0.1 valid=5s` + `set $var` in `proxy_pass` to defer resolution to request time. Includes troubleshooting steps and caveat about loss of `upstream {}` load-balancing features.
- [consul-client-node-identity.md](consul-client-node-identity.md) — Why node identities are used (not a shared prefix policy) for Consul client agent tokens: least-privilege `node:write` scoping, no policy file to maintain, better audit trail. Covers the token-per-node file naming convention, idempotency sentinel, and the node-name-must-match constraint.
- [tls-enabled-troublshooting.md](tls-enabled-troublshooting.md) — Four linked TLS/mTLS bugs found in one session: (1) RFC 5280 violation (empty Subject + non-critical SAN) causing Chrome/Safari to hard-fail on the self-signed cert while Firefox only soft-warns; (2) a self-inflicted mTLS regression from an incomplete `serverAuth`-only Extended Key Usage list that broke Consul/Nomad server-to-server RPC entirely; (3) Consul failing to elect a Raft leader after redeploy because already-running Consul processes never reloaded newly-corrected certs (Go's `crypto/tls` does not hot-reload) — fixed reactively via manual restart and proactively via `notify`-wired restart handlers on all cert-copy tasks; (4) Nomad job placement failures (`${attr.consul.version}` constraint) caused by `consul_dns_token.yaml` Play 3 silently setting `consul_tls_enabled: false` on Consul clients, breaking client→server RPC with `rpc error making call: EOF` while servers still required mTLS. Includes the `openssl x509 -purpose` diagnostic pattern for catching EKU mTLS issues and log signatures for RPC-layer TLS mismatches.

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
controlled by `nomad_client_use_consul_token: true` (set in
`ansible/playbooks/nomad_clients.yaml`). The template block only renders when
`nomad_consul_integration_enabled=true` AND `nomad_consul_workload_identity_enabled=false`.

## Upgrade plans

Stored in [.github/plans/](../../.github/plans/). Each plan documents impact
analysis, file changes, and rollout steps for a specific version upgrade.

| Plan | Versions |
|------|----------|
| [Update2.0.3-2.0.4.md](../../.github/plans/Update2.0.3-2.0.4.md) | Nomad 2.0.3 → 2.0.4 |
