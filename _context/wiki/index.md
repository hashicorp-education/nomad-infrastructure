# nomad-infrastructure Knowledge Wiki

Index of durable knowledge for this project. Use this file to decide whether
to follow a link before acting. Do not read this file in full on every turn —
scan the headings and follow only what is relevant to the current task.

## Architecture and documentation

- [AGENTS.md](../../AGENTS.md) — canonical agent guide: architecture, key commands, conventions, security pitfalls, docs map
- [DEPLOY_CLUSTER_GUIDE.md](../../DEPLOY_CLUSTER_GUIDE.md) — full deployment walkthrough including Terraform + Ansible steps
- [ansible/PLAYBOOKS-README.md](../../ansible/PLAYBOOKS-README.md) — per-playbook reference including variables, tags, and rendered-config inspection
- [ansible/README.md](../../ansible/README.md) — Ansible role/variable overview and troubleshooting guide

## ACL architecture

- [acl-architecture.md](acl-architecture.md) — Complete ACL reference for the cluster: every Consul and Nomad token that exists at runtime, its policy, which agent holds it, and which playbook creates it. Includes rendered `consul.hcl` and `nomad.hcl` ACL blocks, issuance dependency chain, workload identity JWT exchange flow, order-sensitivity rules, and a failure-mode quick-reference table.

## dnsmasq and DNS

- [dnsmasq-consul-docker-dns.md](dnsmasq-consul-docker-dns.md) — How dnsmasq integrates with the OS (systemd-resolved, resolv.conf, config files), why it is required for Consul service discovery, and the Docker task driver DNS failure mode (`172.17.0.1` vs `127.0.0.1`) including the fix (`dnsmasq_listen_addresses` list, group_vars default).

## Troubleshooting

- [troubleshoot-consul-sd.md](troubleshoot-consul-sd.md) — "Counting service is unreachable" in the Countdash web UI when using Consul service discovery. Covers dnsmasq listen address verification, DNS resolution testing from inside the Docker container, cross-node TCP connectivity, Consul health check failure due to slow JVM startup, and **SERVFAIL caused by a stale DNS token file from a previous cluster** (Step 5 — the most common cause after a destroy-and-rebuild cycle).
- [consul-client-node-identity.md](consul-client-node-identity.md) — Why node identities are used (not a shared prefix policy) for Consul client agent tokens: least-privilege `node:write` scoping, no policy file to maintain, better audit trail. Covers the token-per-node file naming convention, idempotency sentinel, and the node-name-must-match constraint.

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
