# Consul client agent ACL — node identity approach

## Decision

Use **node identities** (not a shared custom policy) for Consul client agent
tokens. This is the HashiCorp-recommended approach and is the correct choice
for this project.

## Why node identities are better

### Security — least privilege

A **shared custom policy** with `node_prefix "" { policy = "write" }` grants
every token holder the ability to write _any_ node's entry in the Consul
catalog. A compromised `client-1` token can modify `client-2`'s node
registration, health check status, or deregister it entirely.

A **node identity** scopes `node:write` to the exact named node that the
token was created for. A compromised `client-1` token can only affect
`client-1`'s own catalog entry. Both approaches grant `service:read` on all
services, which is required for catalog queries and DNS.

```
# Custom policy (WRONG) — any client can write any node
node_prefix "" { policy = "write" }   # blast radius = entire catalog

# Node identity (CORRECT) — each client can only write its own node
consul acl token create -node-identity "nomad-consul-client-1:dc1"
# → internally: node "nomad-consul-client-1" { policy = "write" }
#               service_prefix "" { policy = "read" }
```

### Simplicity at scale

Custom policy approach requires:
1. Define policy HCL file
2. Register policy
3. Create N tokens linked to that policy
4. Maintain the policy file over time

Node identity approach requires:
1. `consul acl token create -node-identity "<name>:dc1"` — one command per node
2. No policy file, no policy registration, no policy drift

Adding a new client node = one `token create` command. No policy change needed.

### Token auditing

With node identities, `consul acl token list` shows each token's description
and linked node identity, making it immediately clear which token belongs to
which node. With a shared policy, every token looks identical — you can't tell
which client holds which token from the token list alone.

## Implementation: one token per client node

**Token creation (Play 1 — runs on servers[0]):**

```yaml
- name: Create node-identity agent token for each client
  loop: "{{ groups['clients'] }}"
  ansible.builtin.command: >-
    consul acl token create
    -description "Agent token for {{ item }}"
    -node-identity "{{ item }}:{{ consul_datacenter }}"
```

**Token file naming:** one file per node on the Ansible control machine:
```
ansible/tokens/consul-client-agent-nomad-consul-client-1-secret-id.txt
ansible/tokens/consul-client-agent-nomad-consul-client-2-secret-id.txt
```

**Drop-in config (Play 3 — runs on each client):**
Each client reads its own file using `inventory_hostname`:
```yaml
consul_client_agent_secret_id_file: >-
  {{ inventory_dir }}/tokens/consul-client-agent-{{ inventory_hostname }}-secret-id.txt
```

## Key constraint: node name must match Consul node name

The `-node-identity "<name>:dc1"` value must exactly match the node name that
Consul registers. In this project the consul role sets:
```yaml
consul_node_name: "{{ inventory_hostname }}"
```
so the Ansible `inventory_hostname` (e.g. `nomad-consul-client-1`) is the
correct value. If the consul role is ever changed to use a different node
naming scheme, the token creation loop must be updated to match.

## Idempotency sentinel

Because there are N client agent token files (one per node), the idempotency
check uses the FIRST client's token file as the sentinel. If the file exists,
the entire creation loop is skipped. If any individual file is missing (partial
failure), delete the sentinel file and re-run — the loop will recreate all
tokens.

```
sentinel: consul-client-agent-{{ groups['clients'][0] }}-secret-id.txt
```

## Files affected

| File | Change |
|------|--------|
| `ansible/playbooks/consul_dns_token.yaml` | Play 1: loop with `-node-identity`; Play 3: per-node token file path |
| `ansible/files/consul/consul-client-agent-policy.hcl` | Superseded — no longer used (kept for reference) |

---

## SSRF via Consul HTTP service checks

### The attack vector

Consul supports HTTP health checks. When a service is registered with a check
that points to `http://169.254.169.254/latest/meta-data/iam/security-credentials/`,
the Consul agent makes a GET request to that URL at the configured interval.
If the request succeeds (HTTP 200), the response body — which may contain AWS
IAM credentials — is stored in the Consul health check output and visible to
anyone with `service:read` permission on that service.

### What `service:write` and `node:write` ACL restrictions prevent

Restricting `service:write` to the Nomad agent token only (already the case in
this project via `nomad-client-policy.hcl`) means that:
- Arbitrary processes on the host cannot register services with malicious check URLs
- Only the Nomad agent can register services, and it does so on behalf of submitted jobs

This is a meaningful reduction in attack surface: only an **authorized Nomad
job submitter** can cause SSRF via a crafted job spec. Combined with Nomad ACL
policies that restrict who may submit jobs, the actor population is small.

However, `service:write` ACL does **not** inspect health check URL content.
Consul ACL answers “is this caller allowed to register a service?” — not “is
this health check URL safe?”. A trusted Nomad job can still specify a check
pointing to the EC2 metadata service, and Consul will execute it.

### What actually closes the credential-theft outcome: IMDSv2

AWS Instance Metadata Service v2 (IMDSv2) requires a two-step protocol:
1. `PUT http://169.254.169.254/latest/api/token` with a `X-aws-ec2-metadata-token-ttl-seconds` header — returns a session token
2. `GET http://169.254.169.254/latest/meta-data/...` with `X-aws-ec2-metadata-token: <token>` header

Consul’s HTTP health check only performs a GET request. Without the session
token, the metadata service returns HTTP 401. The health check still fires, but
no credentials are leaked because the response body is an error, not JSON
containing an IAM key.

Enforcing IMDSv2 (`http_tokens = "required"`) in Terraform closes the
credential-theft outcome regardless of what health check URL a Nomad job
specifies.

### Defense-in-depth summary

| Control | What it restricts | Closes credential theft? |
|---------|------------------|--------------------------|
| `service:write` scoped to Nomad agent only | Who can register services with checks | Partially — limits actors |
| Nomad ACL `submit-job` policy | Who can craft the malicious job spec | Partially — reduces population |
| **IMDSv2 (`http_tokens = "required"`)** | **Metadata service rejects GET-only requests** | **Yes** |
| iptables blocking `169.254.0.0/16` | Network-level block | Yes (defence in depth) |



Let me fetch the relevant Consul docs and inspect the project's Consul configuration in parallel.   



Read [](file:///Users/aimeeu/Dev/github/hashicorp-education/nomad-infrastructure/ansible/roles/consul/templates/consul.hcl.j2#1-1), lines 1 to 100

Read [](file:///Users/aimeeu/Dev/github/hashicorp-education/nomad-infrastructure/ansible/roles/consul/defaults/main.yaml#50-50), lines 50 to 60

Fetched 2 resources

Searched for text `acl_enabled|acl_default_policy|consul_acl` (`**/ansible/roles/consul/defaults/main.yaml`), 3 results

Searched for text `client_addr` (`**/ansible/roles/consul/defaults/main.yaml`), 2 results

No matches found. Your search pattern might be excluded completely by either the search.exclude settings or .*ignore files.
If you believe that it should have results, you can check into the .*ignore files and the exclude setting (here are some excluded patterns for reference:[**/node_modules,**/bower_components,**/*.code-search]).
Then if you want to include those files you can call the tool again by setting "includeIgnoredFiles" to true.

Searched for text `consul_acl_enabled|consul_acl_default` (`**/ansible/playbooks/consul_servers.yaml`), 2 results

Read [](file:///Users/aimeeu/Dev/github/hashicorp-education/nomad-infrastructure/ansible/playbooks/consul_servers.yaml#1-1), lines 1 to 70

Read [](file:///Users/aimeeu/Dev/github/hashicorp-education/nomad-infrastructure/ansible/playbooks/consul_clients.yaml#1-1), lines 1 to 60

**Yes — the current configuration does allow this.** There are three compounding factors, and they're already flagged as a security pitfall in AGENTS.md.

---

## How the vulnerability exists in this configuration

### 1. Consul client agents have ACL disabled

consul_clients.yaml explicitly sets:
```yaml
consul_acl_enabled: false
```

When `acl { enabled = false }` is rendered into `consul.hcl` on client nodes, the Consul HTTP API on those nodes requires **no authentication at all**. Any caller — including unauthenticated external requests — can call `PUT /v1/agent/service/register` and supply arbitrary health check URLs.

### 2. The Consul HTTP API listens on all interfaces

main.yaml sets:
```yaml
consul_client_addr: "0.0.0.0"
```

This binds the Consul HTTP API (port 8500) to every network interface on the host, including the public-facing EC2 NIC.

### 3. Port 8500 is open to the internet in the security group

network.tf has:
```hcl
ingress {
  from_port   = 8500
  to_port     = 8500
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  description = "Consul UI and HTTP API"
}
```

**The combined result:** an attacker with knowledge of any Consul client node's public IP can run this from anywhere on the internet:

```bash
curl -X PUT http://<client-public-ip>:8500/v1/agent/service/register \
  -d '{
    "Name": "exploit",
    "Check": {
      "HTTP": "http://169.254.169.254/latest/meta-data/iam/security-credentials/",
      "Interval": "5s"
    }
  }'
```

The Consul client agent accepts the registration (no token required), executes the HTTP GET at the next interval, and the response body is stored in the health check output — readable via the same unauthenticated API.

**IMDSv2** (enforced in compute.tf in the previous step) breaks the credential-theft outcome because the GET to `169.254.169.254` returns 401. But the unauthenticated registration itself still works; it just produces an unhealthy check rather than IAM credentials.

---

## This is already documented as a security pitfall

AGENTS.md lists this explicitly:

> `consul_client_addr` defaults to `0.0.0.0` — the Consul API is reachable on all interfaces. Restrict to `127.0.0.1` in production.

---

## Remediation (layered)

| Fix | Effect | File |
|-----|--------|------|
| **Restrict `consul_client_addr` to `127.0.0.1`** | External callers can't reach the API at all; only local processes (Nomad, dnsmasq) can | consul_clients.yaml |
| Close port 8500 from `0.0.0.0/0` | Removes public network path even if `client_addr` stays broad | network.tf |
| Enable ACL on clients (`consul_acl_enabled: true`) | Requires a valid token with `service:write` to register services | consul_clients.yaml |

The highest-impact single change is setting `consul_client_addr: "127.0.0.1"` on clients, because it eliminates reachability entirely regardless of ACL state. The consul_dns_token.yaml playbook (Play 3) would still work because it communicates with the Consul API from the local host, not from the network.