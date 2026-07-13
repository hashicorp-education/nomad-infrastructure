# nomad_consul Role

Configures the Consul ACL resources required for Nomad to integrate with Consul
using **Nomad Workload Identities** (the modern approach introduced in Nomad 1.7
and the only supported approach from Nomad 1.10 onward).

The role is split into two independent phases that can be run together or separately:

## Phase 1 — Service discovery (`tasks/service_discovery.yaml`)

1. Creates Consul ACL policy for Nomad **server** agents (`nomad-server-policy`)
2. Creates Consul ACL policy for Nomad **client** agents (`nomad-client-policy`)
3. Creates a Consul ACL token for Nomad server agents; saves the SecretID locally
4. Creates a Consul ACL token for Nomad client agents; saves the SecretID locally

The `nomad` role is then re-run with `nomad_consul_integration_enabled: true` to write
the `consul { address token }` block into `/etc/nomad.d/nomad.hcl`.

## Phase 2 — Workload identity (`tasks/workload_identity.yaml`)

5. Creates a Consul JWT **auth method** (`nomad-workloads`) that accepts Nomad workload identity JWTs
6. Creates a Consul **binding rule** mapping service workload identities to a Consul service identity
7. Creates a Consul ACL policy for Nomad task workload identities (`nomad-tasks-policy`)
8. Creates a Consul ACL **role** (`nomad-tasks-default`) for tasks in the Nomad `default` namespace
9. Creates a Consul **binding rule** mapping task workload identities to the `nomad-tasks-default` role

The `nomad` role is then re-run with `nomad_consul_workload_identity_enabled: true` to add
`service_identity` and `task_identity` blocks to the `consul {}` section on Nomad servers.

All operations in each phase are guarded by their own sentinel file and run exactly once per cluster.

## Prerequisites

- Consul cluster deployed and healthy (`playbooks/consul_servers.yaml` + `playbooks/consul_clients.yaml`)
- Consul ACL bootstrapped (`playbooks/consul_acl_bootstrap.yaml`)
- `ansible/tokens/consul-bootstrap-secret-id.txt` present
- The Nomad cluster must be deployed and running (its JWKS endpoint must be
  reachable by Consul servers for the JWT auth method to work)

## Local output files

After a successful run the following files are written to `ansible/tokens/` on the Ansible control
machine (mode `0600`):

| File | Contents |
|------|----------|
| `ansible/tokens/nomad-consul-server-token-output.txt` | Full `consul acl token create` output for the Nomad server token |
| `ansible/tokens/nomad-consul-server-secret-id.txt` | SecretID only — consumed by `consul_nomad_service_discovery.yaml` |
| `ansible/tokens/nomad-consul-client-token-output.txt` | Full `consul acl token create` output for the Nomad client token |
| `ansible/tokens/nomad-consul-client-secret-id.txt` | SecretID only — consumed by `consul_nomad_service_discovery.yaml` |

These files contain sensitive credentials. They are git-ignored by default; do
not commit them.

## Key variables

### Phase control flags

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_consul_run_service_discovery` | `true` | Set `false` to skip Phase 1 when calling the role directly |
| `nomad_consul_run_workload_identity` | `true` | Set `false` to skip Phase 2 |

**To run service discovery only** (no JWT auth method, no binding rules):

```yaml
- role: nomad_consul
  vars:
    nomad_consul_run_workload_identity: false
```

Or use the dedicated playbook:

```bash
ansible-playbook -i inventory.ini consul_nomad_service_discovery.yaml
```

### Connection and path variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_consul_http_addr` | `http://127.0.0.1:8500` | Consul HTTP API address |
| `nomad_consul_bin_path` | `/usr/local/bin/consul` | Path to Consul binary |
| `nomad_consul_bootstrap_secret_id_file` | `{{ inventory_dir }}/tokens/consul-bootstrap-secret-id.txt` | Local file with Consul bootstrap SecretID |

### JWT auth method variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nomad_consul_jwks_url` | First server HTTP address on port 4646 | JWKS URL Consul servers use to validate Nomad JWTs; point to a load balancer in production |
| `nomad_consul_auth_method_name` | `nomad-workloads` | Consul JWT auth method name |
| `nomad_consul_tasks_role_name` | `nomad-tasks-default` | Consul ACL role for Nomad tasks in the default namespace |

Refer to [`defaults/main.yaml`](defaults/main.yaml) for the full variable reference.

## Architecture

```
Nomad Workload (task or service)
        │
        │  JWT (signed by Nomad)
        ▼
Consul JWT Auth Method  ◄── JWKS URL ──► Nomad /.well-known/jwks.json
        │
        ├── "nomad_service" in JWT  ──►  Binding Rule  ──►  Service Identity
        │                                                    (register/manage service)
        │
        └── "nomad_service" NOT in JWT ─► Binding Rule  ──►  Role: nomad-tasks-default
                                                              (read services / KV)
```

## References

- [Integrate Consul ACL](https://developer.hashicorp.com/nomad/docs/secure/acl/consul)
- [Configure Consul ACL with Nomad Workload Identities](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-acl)
