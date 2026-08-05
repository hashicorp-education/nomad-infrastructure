# Update Nomad 2.0.3 → 2.0.4

## Summary

Patch (fix) release upgrade. No breaking changes in 2.0.4. Primary change is the
version pin in `ansible/group_vars/all.yaml`. One optional config addition to
`ansible/roles/nomad/templates/nomad.hcl.j2` supports the new Consul token
fallback for workloads that use `template` blocks without workload identity.

Rolling upgrade order: Nomad servers (serial: 1 to preserve 3-node quorum) →
Nomad clients.

## 2.0.4 Impact Analysis

| Item | Impact | Action |
|------|--------|--------|
| `server.retry_join/interval/max/start_join` removed in 2.1.0 | Future risk | Template already uses `server_join { retry_join }` block — COMPLIANT |
| Unauthenticated `server join` CLI deprecated | Future risk | Operational only, no config change |
| Consul token fallback (`use_client_consul_token`) | New optional feature | Add conditional block to `nomad.hcl.j2` client section |
| `run_on_first_render` in `change_script` | Job-spec only | No agent config change |
| Docker `allowed_modes` | Optional plugin config | No change unless namespace isolation needed |
| Task driver `Init`/`Shutdown` | Plugin author API | No config change |

## Files Changed

### `ansible/group_vars/all.yaml`
Bumped `nomad_binary_version` from `"2.0.3"` to `"2.0.4"`.

### `ansible/roles/nomad/defaults/main.yaml`
Added `nomad_client_use_consul_token: false` — controls whether the Nomad client
agent's own Consul token is made available to `template` blocks. Introduced in
Nomad 2.0.4 for deployments that use Consul integration without workload identity.

### `ansible/roles/nomad/templates/nomad.hcl.j2`
Added a conditional `template { use_client_consul_token = true }` sub-block inside
the `client {}` block, guarded by:
- `nomad_consul_integration_enabled` — Consul integration is active
- `not nomad_consul_workload_identity_enabled` — workload identity is not in use
- `nomad_client_use_consul_token` — opt-in flag (default: false)

### `ansible/roles/nomad/meta/argument_specs.yaml`
Added spec entry for the new `nomad_client_use_consul_token` variable.

### `ansible/roles/nomad/tasks/main.yaml`
Added a `nomad validate` task (tagged `nomad_validate`) after the configuration
template task. This validates the rendered HCL before any service restart handler
fires, catching broken config before it causes a service outage.

## Rolling Upgrade Steps

### Pre-upgrade
```bash
nomad server members
nomad node status
nomad version
```

### Step 1 — Upgrade Nomad servers (one at a time)
```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/nomad_servers.yaml --serial 1
```
After each server: `nomad server members` to confirm all alive, one leader.

### Step 2 — Upgrade Nomad clients
```bash
ansible-playbook -i inventory.ini playbooks/nomad_clients.yaml
```

### Step 3 — Verify cluster health
```bash
nomad server members    # 3 servers, one leader
nomad node status       # both clients ready
nomad version           # 2.0.4 on all nodes
```

## Optional: Enable Consul Token Fallback

For deployments using the `deploy_consul_nomad_sd.yaml` scenario (Consul
integration without workload identity) where jobs use `template` blocks reading
Consul KV or services, set the following in host/group vars:

```yaml
nomad_client_use_consul_token: true
```

Also add the following policy to the Consul ACL policy used by Nomad client agents:

```hcl
key_prefix "" {
  policy = "read"
}
```

Reference: https://developer.hashicorp.com/nomad/docs/secure/acl/consul#consul-without-workload-identity
