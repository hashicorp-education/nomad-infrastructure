# ACL architecture

This document describes the complete ACL setup for the Consul and Nomad
clusters in this project: every token that exists at runtime, the policy it
carries, which agent holds it, which playbook creates it, and why each
permission is needed.

The two ACL systems (Consul and Nomad) are independent. Both use
**default-deny**: any API call or DNS query without a valid token is rejected.
Both are bootstrapped automatically by the use case entrypoints — there is no
manual ACL setup required unless you are running sub-playbooks individually.

---

## 1. Consul ACL model

Consul ACL has four concepts that matter here:

| Concept | Description |
|---------|-------------|
| **Policy** | A named set of HCL rules (`node_prefix`, `service_prefix`, `acl`, etc.) |
| **Token** | A UUID that carries one or more policies. Sent in the `X-Consul-Token` header or env var `CONSUL_HTTP_TOKEN`. |
| **Anonymous token** | The built-in token with ID `00000000-0000-0000-0000-000000000002`. Used when no token is supplied. Default-deny means it has no permissions by default. |
| **Agent token** | A per-agent configured token (`acl.tokens.agent` or `acl.tokens.dns` in `consul.hcl`, or set via `consul acl set-agent-token`). Used for the agent's own catalog operations. |

This project sets `default_policy = "deny"`. Every API call, health check
route, and DNS query must carry a token with sufficient permissions.

## 2. Nomad ACL model

Nomad ACL is simpler: a token carries **namespace policies** and **node
policies**. This project bootstraps the ACL system and stops there — no
additional Nomad policies or tokens are created by these playbooks. Operators
create job-submission tokens as needed after the cluster is running.

---

## 3. Token inventory

Every token that exists after a successful deployment. Columns show:
- **Holder** — which process or person has this token at runtime
- **Mechanism** — how the token is delivered to the holder
- **Playbook** — which sub-playbook creates it

### Consul tokens

| Token name | Holder | Policy | Mechanism | Playbook |
|-----------|--------|--------|-----------|---------|
| Bootstrap token | Operator (control machine) | `global-management` (full access) | Saved to `ansible/tokens/consul-bootstrap-secret-id.txt` (mode 0600) | `consul_acl_bootstrap.yaml` |
| DNS token | Every Consul agent (servers + clients) | `dns-access` | Servers: `consul acl set-agent-token dns` + data-dir persistence. Clients: `acl.tokens.dns` in `consul.hcl` | `consul_dns_token.yaml` |
| Per-node client agent token | Each Consul client agent | Node identity for that node (implicit: `node:write` on THIS node, `service_prefix:read` on all) | `acl.tokens.agent` in `consul.hcl` | `consul_dns_token.yaml` |
| Nomad server Consul token | Each Nomad server agent | `nomad-server-policy` | `consul.token` in `nomad.hcl` | `consul_nomad_service_discovery.yaml` |
| Nomad client Consul token | Each Nomad client agent | `nomad-client-policy` | `consul.token` in `nomad.hcl` | `consul_nomad_service_discovery.yaml` |
| Anonymous token (built-in) | Any unauthenticated request | `anonymous-deny` (explicit deny-all) | Applied to built-in token `00000000-...` | `consul_acl_deny_anonymous.yaml` |

**Workload identity only** (scenario D — `deploy_consul_nomad_wi.yaml`):

| Resource | Type | Purpose | Playbook |
|---------|------|---------|---------|
| `nomad-workloads` JWT auth method | Auth method | Validates JWTs signed by Nomad JWKS endpoint; Nomad workloads exchange them for Consul tokens at runtime | `consul_nomad_workload_identity.yaml` |
| `nomad-tasks-default` ACL role | Role | Assigned to task workload JWTs via binding rule; carries `nomad-tasks-policy` | `consul_nomad_workload_identity.yaml` |

With workload identity enabled, Nomad jobs do **not** use the Nomad client
Consul token for catalog operations. Instead, each workload gets its own
short-lived Consul token exchanged from a JWT — there are no static tokens in
job specs.

### Nomad tokens

| Token name | Holder | Policy | Mechanism | Playbook |
|-----------|--------|--------|-----------|---------|
| Bootstrap token | Operator (control machine) | `global-management` (full access) | Saved to `ansible/tokens/nomad-bootstrap-secret-id.txt` (mode 0600) | `nomad_acl_bootstrap.yaml` |

No other Nomad tokens are created by these playbooks. Create namespace/node
policy tokens post-deployment for operators and CI systems.

---

## 4. Policy definitions

Policy files live in `ansible/files/consul/`. They are pushed to the server
during the relevant playbook and registered with `consul acl policy create`.

### `dns-policy.hcl` — used by the DNS token

```hcl
node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

query_prefix "" {
  policy = "read"
}
```

**Why these permissions:**
- `node_prefix "" read` — Consul DNS needs to read node records to resolve
  `<node>.node.global` and to map service instances to their node addresses.
- `service_prefix "" read` — Required to resolve any `<name>.service.global`
  lookup. Without this, every `.global` DNS query returns SERVFAIL even if the
  service exists.
- `query_prefix "" read` — Required for Consul prepared queries (used by some
  service mesh patterns). Included for completeness; not strictly required for
  basic service discovery.

### `nomad-server-policy.hcl` — used by Nomad server agents

```hcl
agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}

acl  = "write"
mesh = "write"
```

**Why these permissions:**
- `agent_prefix "" read` — Nomad servers query the Consul agent HTTP API to
  check agent status and coordinate with the local Consul agent.
- `node_prefix "" write` — Nomad servers register themselves as nodes in the
  Consul catalog (`nomad` and `nomad-client` services).
- `service_prefix "" write` — Nomad servers register/deregister Nomad services
  and health checks. Every Nomad job service block becomes a Consul service.
- `acl = "write"` — Required by Nomad servers to create and manage Consul ACL
  tokens for workload identity (Nomad requests scoped tokens from Consul on
  behalf of workloads). Without this, the `consul_nomad_workload_identity.yaml`
  playbook succeeds but Nomad cannot request tokens at runtime.
- `mesh = "write"` — Required if Consul Connect (service mesh) is enabled. Not
  used by default in this project (`consul_connect_enabled: false`), but
  included because Nomad's consul block documentation recommends it for
  forward compatibility.

### `nomad-client-policy.hcl` — used by Nomad client agents

```hcl
agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}

key_prefix "" {
  policy = "read"
}
```

**Why these permissions:**
- `agent_prefix "" read` — Nomad clients communicate with the local Consul agent.
- `node_prefix "" write` — Nomad clients register node metadata.
- `service_prefix "" write` — Nomad clients register/deregister services and
  health checks for every allocation running on the node.
- `key_prefix "" read` — Nomad `template` blocks read Consul KV when
  `nomad_consul_integration_enabled: true` and
  `nomad_consul_workload_identity_enabled: false` (i.e., service discovery
  without workload identity). Without this, `template` blocks that use
  `{{key "path/to/value"}}` fail at render time.

**Note:** In the workload identity scenario (`deploy_consul_nomad_wi.yaml`),
`template` blocks use the workload's own Consul token instead of the client's
token. The `key_prefix read` grant is still harmless in that case.

### `nomad-tasks-policy.hcl` — used by Nomad task workload identities

```hcl
key_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
```

**Why these permissions:** This policy is assigned to the `nomad-tasks-default`
role, which task workload identity JWTs (from Nomad's task identity) map to.
Tasks using `template` blocks need to read KV and resolve service addresses.
`node_prefix read` is required alongside `service_prefix read` for DNS-based
service discovery to work from within the template renderer.

**Production note:** All three prefixes are empty strings, granting read
access to all KV paths and all services. For a production cluster, scope these
to the paths and service names your jobs actually need.

### `consul-anonymous-deny.hcl` — applied to the anonymous token

```hcl
acl = "deny"

agent_prefix "" {
  policy = "deny"
}

event_prefix "" {
  policy = "deny"
}

key_prefix "" {
  policy = "deny"
}

node_prefix "" {
  policy = "deny"
}
# (service, query, etc. omitted for brevity — all deny)
```

**Why this policy exists:** With `default_policy = "deny"`, unauthenticated
requests are already rejected by default. The explicit deny-all policy on the
anonymous token is a defense-in-depth measure: it prevents a future policy
merge from accidentally granting the anonymous token permissions via an
overlapping policy. Any rule attached to the anonymous token uses the most
permissive value in the rule set, so making all rules explicit `deny` closes
that vector.

**Order constraint:** This policy must be applied **after** `consul_dns_token.yaml`
completes. If it runs first, the DNS token does not yet exist and the DNS
agent token slot is empty on clients, causing every DNS query to fall back to
the anonymous token — which, once denied, produces SERVFAIL for all `.global`
lookups.

---

## 5. Issuance chain and dependencies

Each token depends on the previous layer being in place. Running a playbook
out of order will fail at the token creation or application step.

```
consul_acl_bootstrap.yaml
  └── writes: consul-bootstrap-secret-id.txt
        │
        ├── consul_dns_token.yaml (Play 1) ← requires bootstrap token
        │     ├── creates: dns-access policy
        │     ├── creates: DNS token → consul-dns-secret-id.txt
        │     ├── creates: node-identity token per client
        │     │       → consul-client-agent-<hostname>-secret-id.txt
        │     │
        │     ├── consul_dns_token.yaml (Play 2) ← applies DNS token to servers
        │     │     set-agent-token dns → persisted to server data dir
        │     │
        │     └── consul_dns_token.yaml (Play 3) ← reconfigures clients
        │           re-runs consul role with consul_acl_enabled=true
        │           writes consul.hcl: acl { tokens { agent dns } }
        │
        ├── consul_acl_deny_anonymous.yaml ← must run AFTER dns_token
        │     applies anonymous-deny policy to anonymous token
        │
        └── consul_nomad_service_discovery.yaml (Play 1) ← requires bootstrap + nomad running
              creates: nomad-server-policy → nomad-consul-server-secret-id.txt
              creates: nomad-client-policy → nomad-consul-client-secret-id.txt
                    │
                    ├── consul_nomad_service_discovery.yaml (Play 2)
                    │     re-runs nomad role on servers: writes consul { token } to nomad.hcl
                    │
                    ├── consul_nomad_service_discovery.yaml (Play 3)
                    │     re-runs nomad role on clients: writes consul { token } to nomad.hcl
                    │
                    └── consul_nomad_workload_identity.yaml (Play 1) [scenario D only]
                          requires nomad-consul-server-secret-id.txt (Nomad JWKS endpoint)
                          creates: nomad-tasks-policy
                          creates: nomad-workloads JWT auth method
                          creates: service binding rule (nomad_service → service identity)
                          creates: nomad-tasks-default role
                          creates: task binding rule (nomad_task → nomad-tasks-default)

nomad_acl_bootstrap.yaml (independent of Consul ACL)
  └── writes: nomad-bootstrap-secret-id.txt
```

---

## 6. What the rendered agent configs look like

### Consul server agent (`/etc/consul.d/consul.hcl`)

After `consul_servers.yaml`:

```hcl
# (network, ports, server, retry_join sections omitted)

acl {
  enabled                  = true
  default_policy           = "deny"
  enable_token_persistence = true
}
```

The `tokens {}` block is absent — `consul_acl_agent_token` and
`consul_acl_dns_token` are both empty when `consul_servers.yaml` runs. The DNS
token is applied later via `consul acl set-agent-token dns` (Play 2 of
`consul_dns_token.yaml`) and persisted to the server data directory by Consul's
token persistence mechanism. Re-running `consul_servers.yaml` alone does not
disturb the persisted token.

### Consul client agent (`/etc/consul.d/consul.hcl`)

After `consul_clients.yaml` (initial deploy — ACL disabled):

```hcl
acl {
  enabled = false
}
```

After `consul_dns_token.yaml` Play 3 re-runs the consul role (ACL enabled):

```hcl
acl {
  enabled                  = true
  default_policy           = "deny"
  enable_token_persistence = true
  tokens {
    agent = "<node-identity-token-secretid>"
    dns   = "<shared-dns-token-secretid>"
  }
}
```

The `agent` value is the per-node node-identity token read from
`ansible/tokens/consul-client-agent-<inventory_hostname>-secret-id.txt`.
The `dns` value is the shared DNS token from
`ansible/tokens/consul-dns-secret-id.txt`.

### Nomad server agent (`/etc/nomad.d/nomad.hcl`)

Before service discovery (after `nomad_servers.yaml`):

```hcl
acl {
  enabled = true
}
```

After `consul_nomad_service_discovery.yaml`:

```hcl
acl {
  enabled = true
}

consul {
  address = "127.0.0.1:8500"
  token   = "<nomad-consul-server-token-secretid>"
}
```

After `consul_nomad_workload_identity.yaml` (scenario D only):

```hcl
consul {
  address = "127.0.0.1:8500"
  token   = "<nomad-consul-server-token-secretid>"

  service_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }

  task_identity {
    aud = ["consul.io"]
    ttl = "1h"
  }
}
```

`service_identity` and `task_identity` tell Nomad servers to inject
workload identity JWTs into every job. These JWTs are exchanged for Consul
tokens at allocation time — the `token` field in the consul block is the
Nomad server's own agent token, not a token for workloads.

### Nomad client agent (`/etc/nomad.d/nomad.hcl`)

After `consul_nomad_service_discovery.yaml`:

```hcl
acl {
  enabled = true
}

client {
  enabled = true
  # ...

  template {
    use_client_consul_token = true
  }
}

consul {
  address = "127.0.0.1:8500"
  token   = "<nomad-consul-client-token-secretid>"
}
```

`use_client_consul_token = true` causes Nomad to pass the client's Consul
token through to `template` block rendering. Without this, templates that call
`{{key "..."}}` or `{{service "..."}}` would use no token and fail with
permission denied errors. This setting has no effect in the workload identity
scenario because `use_client_consul_token` is only respected when
`nomad_consul_workload_identity_enabled: false`.

---

## 7. Workload identity token exchange (scenario D)

This flow applies only when `deploy_consul_nomad_wi.yaml` is used.

```
Nomad server                Nomad client                Consul agent
     │                           │                           │
     │   Job dispatch             │                           │
     │──────────────────────────>│                           │
     │                           │                           │
     │   Inject JWT (service_identity / task_identity)       │
     │──────────────────────────>│                           │
     │                           │                           │
     │             Allocation starts, task needs Consul token │
     │                           │─── POST /v1/acl/login ───>│
     │                           │    { AuthMethod: "nomad-workloads",
     │                           │      BearerToken: <JWT signed by Nomad JWKS> }
     │                           │                           │
     │                           │    Consul validates JWT   │
     │                           │    against Nomad JWKS URL │
     │                           │    (http://<server>:4646/.well-known/jwks.json)
     │                           │                           │
     │                           │    Binding rule matches:  │
     │                           │    nomad_service claim    │
     │                           │    → Consul service identity
     │                           │    OR nomad_task claim    │
     │                           │    → nomad-tasks-default role
     │                           │                           │
     │                           │<── scoped Consul token ───│
     │                           │    (TTL: 1h, auto-refreshed)
     │                           │                           │
     │                           │   Task uses token for     │
     │                           │   template / service reg  │
```

The JWT is signed by Nomad using the keypair at
`http://<first-server>:4646/.well-known/jwks.json`. Consul validates the
signature before issuing a token. The resulting token expires after the TTL
(`1h` by default) and is automatically renewed by the Nomad client while the
allocation is running.

**Why this is better than a shared static token:** Each workload gets a token
scoped exactly to its service name (via Consul service identities) or to the
`nomad-tasks-policy` read-only grant. A compromise of one allocation's token
cannot be used to write any other service or modify the catalog.

---

## 8. Order sensitivity

Several ACL operations must happen in a specific order or the cluster will be
misconfigured in a way that is not always obvious from error messages.

### consul_dns_token.yaml before consul_acl_deny_anonymous.yaml

The DNS token must exist and be applied to every agent **before** the
anonymous token is denied. If the anonymous token is denied first, `.global`
DNS queries return SERVFAIL until the DNS token is in place. The use case
entrypoints (`deploy_consul.yaml`, `deploy_consul_nomad_sd.yaml`,
`deploy_consul_nomad_wi.yaml`) enforce this order automatically.

### consul_acl_bootstrap.yaml before any token creation

The bootstrap token file (`consul-bootstrap-secret-id.txt`) is read by every
subsequent token-creation playbook. If it is missing, all downstream playbooks
fail at the task that reads the file.

### consul_nomad_service_discovery.yaml after nomad is running

Play 2 and Play 3 of `consul_nomad_service_discovery.yaml` restart the Nomad
service after writing the Consul token to `nomad.hcl`. If Nomad is not yet
running, the restart step fails. Run `nomad_servers.yaml` and
`nomad_clients.yaml` before this playbook.

### consul_nomad_workload_identity.yaml after consul_nomad_service_discovery.yaml

The workload identity playbook reads `nomad-consul-server-secret-id.txt` to
construct the JWKS URL used in the JWT auth method. This file is created by
the service discovery playbook.

---

## 9. Token file locations and lifecycle

All token files are on the **Ansible control machine** (not on the cluster
nodes) in `ansible/tokens/`. Files are created with mode 0600.

| File | Created by | Notes |
|------|-----------|-------|
| `consul-bootstrap-secret-id.txt` | `consul_acl_bootstrap.yaml` | Idempotency sentinel — if present, bootstrap is skipped |
| `consul-dns-secret-id.txt` | `consul_dns_token.yaml` | Idempotency sentinel — if present, DNS token creation is skipped |
| `consul-client-agent-<hostname>-secret-id.txt` | `consul_dns_token.yaml` | One per client; sentinel checks first client's file |
| `nomad-bootstrap-secret-id.txt` | `nomad_acl_bootstrap.yaml` | Idempotency sentinel |
| `nomad-consul-server-secret-id.txt` | `consul_nomad_service_discovery.yaml` | Sentinel for Nomad/Consul integration |
| `nomad-consul-client-secret-id.txt` | `consul_nomad_service_discovery.yaml` | Sentinel for Nomad/Consul integration |

**After `terraform destroy`:** The cluster is gone but these files persist.
On the next deployment, every idempotency check sees the files and skips token
creation. The new cluster has no matching tokens — any operation that uses
those UUIDs will receive a 403, and `.global` DNS queries will return SERVFAIL.

**Recovery:** Delete all files in `ansible/tokens/` before re-deploying:

```bash
rm ansible/tokens/*.txt
```

Or run `teardown.yaml` before destroying, which deletes the token files as
part of its cleanup (Play 7 tagged `teardown_tokens`).

---

## 10. Common ACL failure modes

| Symptom | Most likely cause | Verification | Fix |
|---------|------------------|--------------|-----|
| `.global` DNS returns SERVFAIL | Stale DNS token file from a previous cluster | `consul acl token list` — DNS token UUID not present | Delete `consul-dns-secret-id.txt`, re-run `consul_dns_token.yaml` |
| `.global` DNS returns NXDOMAIN | Consul not running or ACL not yet configured | `systemctl status consul` | Run `consul_servers.yaml` / `consul_clients.yaml` |
| Nomad job service registration fails (permission denied) | Nomad client Consul token missing or wrong | `nomad alloc logs <id>` shows 403 | Re-run `consul_nomad_service_discovery.yaml` |
| Workload identity JWT validation fails | JWKS URL unreachable or Nomad server port 4646 not accessible | `consul acl auth-method read -name nomad-workloads` — check JWKS URL | Verify Nomad server is running; re-run `consul_nomad_workload_identity.yaml` |
| Consul API returns 403 on everything | Anonymous token denied before DNS token was set | `consul acl token read -id 00000000-0000-0000-0000-000000000002` | Re-run `consul_dns_token.yaml`, then `consul_acl_deny_anonymous.yaml` |
| Consul `acl bootstrap` fails "ACL bootstrap already done" | Bootstrap already ran; token file was deleted | Check cluster state | Run `consul_acl_bootstrap.yaml` — it detects already-bootstrapped state and exits cleanly; token file was the idempotency guard, not the cluster state |

---

## Related files

- [`ansible/files/consul/`](../../ansible/files/consul/) — Policy HCL files
- [`ansible/playbooks/consul_dns_token.yaml`](../../ansible/playbooks/consul_dns_token.yaml) — DNS token and client agent token issuance
- [`ansible/playbooks/consul_acl_deny_anonymous.yaml`](../../ansible/playbooks/consul_acl_deny_anonymous.yaml) — Anonymous token hardening
- [`ansible/playbooks/consul_nomad_service_discovery.yaml`](../../ansible/playbooks/consul_nomad_service_discovery.yaml) — Nomad agent tokens
- [`ansible/playbooks/consul_nomad_workload_identity.yaml`](../../ansible/playbooks/consul_nomad_workload_identity.yaml) — JWT auth method and binding rules
- [`ansible/roles/consul/templates/consul.hcl.j2`](../../ansible/roles/consul/templates/consul.hcl.j2) — Consul config template (renders `acl.tokens`)
- [`ansible/roles/nomad/templates/nomad.hcl.j2`](../../ansible/roles/nomad/templates/nomad.hcl.j2) — Nomad config template (renders `consul` block)
- [consul-client-node-identity.md](consul-client-node-identity.md) — Design rationale for per-node agent tokens vs shared prefix policy
- [troubleshoot-consul-sd.md](troubleshoot-consul-sd.md) — Stale token SERVFAIL debugging steps
