# nomad-infrastructure Knowledge Wiki

Index of durable knowledge for this project. Use this file to decide whether
to follow a link before acting. Do not read this file in full on every turn —
scan the headings and follow only what is relevant to the current task.

## Architecture and documentation

- [AGENTS.md](../../AGENTS.md) — canonical agent guide: architecture, key commands, conventions, security pitfalls, docs map
- [DEPLOY_CLUSTER_GUIDE.md](../../DEPLOY_CLUSTER_GUIDE.md) — full deployment walkthrough including Terraform + Ansible steps
- [ansible/PLAYBOOKS-README.md](../../ansible/PLAYBOOKS-README.md) — per-playbook reference including variables, tags, and rendered-config inspection
- [ansible/README.md](../../ansible/README.md) — Ansible role/variable overview and troubleshooting guide

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
