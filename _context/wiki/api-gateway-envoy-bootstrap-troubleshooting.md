# Consul API Gateway: Envoy bootstrap failures and stale mesh registrations

Six linked issues found while getting `nomad-jobs/consul-mesh/api-gateway.nomad.hcl`
(rollout step 6 of [consul-service-mesh-plan.md](consul-service-mesh-plan.md))
to a genuinely healthy, end-to-end-working state — not just "deployment
successful" in Nomad, but an actual HTTPS request proxied through to a mesh
backend. The first three are gateway job bugs; the fourth is a Consul catalog
hygiene issue unrelated to the gateway itself, included here because its
symptom (503 from a healthy-looking gateway) is easy to misattribute back to
the gateway; the fifth is a missing Nomad ACL policy; the sixth is a local
CLI/server version-skew issue that reproduces the exact same 503 symptom as
the fourth but with a completely different root cause and fix.

## 1. `hashicorp/consul` images do not bundle `envoy`

`consul connect envoy -gateway=api -register` needs both the `consul` and
`envoy` binaries in the same container. `hashicorp/consul:2.0.2` does not
ship `envoy` at all, and there is no `hashicorp/consul-envoy` image (verified
via the Docker Hub v2 API — that repository does not exist).

**Fix — invert which binary is "native" to the image, don't just copy across:**

- Copying the glibc-linked `envoy` binary from `envoyproxy/envoy` into the
  Alpine/musl-based `hashicorp/consul` image fails at runtime:
  ```
  Error relocating /alloc/envoy: pthread_cond_clockwait: symbol not found
  Error relocating /alloc/envoy: __res_init: symbol not found
  ```
  musl's dynamic linker cannot satisfy glibc-specific symbols. This direction
  does not work no matter how the copy is performed.
- The other direction works because HashiCorp ships `consul` as a
  **statically-linked Go binary** (`CGO_ENABLED=0`) with no libc dependency —
  it runs unmodified on any Linux base image regardless of libc flavor.

Final structure: a `lifecycle { hook = "prestart", sidecar = false }` task on
the `hashicorp/consul:2.0.2` image copies the binary into the shared `alloc/`
directory:

```hcl
task "fetch-consul" {
  driver = "docker"
  lifecycle {
    hook    = "prestart"
    sidecar = false
  }
  config {
    image      = "hashicorp/consul:2.0.2"
    entrypoint = ["/bin/sh", "-c"]
    args = [
      "cp \"$(command -v consul)\" /alloc/consul && chmod +x /alloc/consul",
    ]
  }
}
```

The main `gateway` task then runs on `envoyproxy/envoy:v1.38.2` (envoy
already on `PATH`) and execs `/alloc/consul connect envoy ...` instead of
`consul connect envoy ...`.

## 2. (Corollary of #1) musl vs. glibc binary portability rule

General rule confirmed by this investigation, useful beyond this one job:

> Statically-linked Go binaries (built with `CGO_ENABLED=0`) are portable
> across musl/glibc base images. Dynamically-linked binaries (most things
> built with cgo, C/C++ tools, or shipped from Ubuntu/Debian-based images
> like `envoyproxy/envoy`) are **not** — they cannot be copied into an
> Alpine/musl image. When you need two tools from different base images in
> one container, copy the static one into the dynamic one's native image,
> not the reverse.

## 3. `CONSUL_GRPC_ADDR` needs an explicit `https://` scheme when `grpc_tls` is in use

This cluster runs `consul_port_grpc_tls: 8503` (TLS-only xDS/gRPC port — see
[consul-service-mesh-plan.md §4](consul-service-mesh-plan.md#4-consul-agent-config-changes)),
while `consul_port_grpc` (plaintext, port 8502) is Consul's default and
always available regardless of TLS settings.

Setting `CONSUL_GRPC_ADDR = "${attr.unique.network.ip-address}:8503"`
(bare `IP:port`, no scheme) does **not** error immediately. Instead, `consul
connect envoy` silently generates a Envoy bootstrap whose `local_agent`
cluster has **no `transport_socket` at all** (plaintext h2c) — even though
it's pointed at a TLS-only port. Envoy then loops forever with a vague error
that gives no hint that TLS is the problem:

```
DeltaAggregatedResources gRPC config stream to local_agent closed since 30s ago: 14,
upstream connect error or disconnect/reset before headers. reset reason: connection_termination
```

**Diagnosis technique:** `consul connect envoy` supports a `-bootstrap` flag
that dumps the generated bootstrap JSON to stdout instead of exec'ing Envoy.
Temporarily replace the `exec ... consul connect envoy ...` command with the
same command plus `-bootstrap > /alloc/bootstrap.json` (no `exec`, so the
task can still copy the file out via `nomad alloc fs`), then grep the
`local_agent` cluster definition for `transport_socket`. Its absence
confirms a plaintext-cluster-against-TLS-port mismatch. Remove the debug
flag once confirmed — it's a one-shot diagnostic, not something to leave in
the job.

**Fix:** prefix the scheme:

```hcl
env {
  CONSUL_HTTP_ADDR       = "https://${attr.unique.network.ip-address}:8443"
  CONSUL_GRPC_ADDR       = "https://${attr.unique.network.ip-address}:8503"
  CONSUL_TLS_SERVER_NAME = "client.dc1.global"
}
```

Per the [`consul connect envoy` docs](https://developer.hashicorp.com/consul/commands/connect/envoy),
gRPC "uses the same TLS settings as the HTTPS API. If HTTPS is enabled then
gRPC will require HTTPS as well" — the scheme prefix on `CONSUL_GRPC_ADDR` (or
alternatively `CONSUL_HTTP_SSL=true`) is what actually activates that TLS
config path, and it's easy to miss since the CLI doesn't validate or warn
about the mismatch up front.

Once fixed, this was the last gateway-side bug: deployment reached "Deployment
completed successfully" with Envoy CDS/LDS loading and a working HTTPS
listener on port 8447, confirmed with an external `curl -sk
https://<client-ip>:8447/` TLS handshake.

## 4. 503 from a healthy gateway: stale Consul catalog entries, not a gateway bug

After the gateway itself was confirmed healthy, routing a real request to
`countdash-web` (via `http-route-countdash.hcl`) returned:

```
HTTP 503
upstream connect error or disconnect/reset before headers. reset reason: remote connection failure
```

Diagnostic chain (each step ruled out one layer):

1. Intentions: `consul intention check api-gateway countdash-web` → allowed. Not the cause.
2. Consul health API: `countdash-web` service itself showed "passing". Not obviously the cause.
3. Consul health API: `countdash-web-sidecar-proxy` returned **three** registered
   instances across two node IPs/ports — more than the single running
   replica should produce.
4. Envoy admin API (`/clusters`, reached via a `/dev/tcp` bash workaround —
   see below) showed nonzero `cx_connect_fail` on the stale endpoints.
5. Direct TCP/TLS connectivity tests (`/dev/tcp`, `openssl s_client`) from
   inside the gateway container to the stale ports returned immediate
   **"Connection refused"** (a TCP RST — nothing listening — not a firewall
   drop, which would time out instead).
6. AWS security group: ruled out — `aws_security_group.nomad_consul_sg` in
   `terraform/aws/network.tf` has a self-referencing "allow all internal
   traffic" rule (`protocol = "-1"`, `self = true`), so intra-VPC traffic on
   any port is never blocked at the SG layer in this repo. Don't
   re-investigate this as a cause in future sessions.
7. **Root cause:** `nomad job status` showed `countdash-mesh` was `dead
   (stopped)`. The live sidecar-proxy registration was gone, but **two
   stale registrations remained in Consul's catalog reporting "passing"**
   from a prior incarnation of the job/agent. Envoy load-balanced across
   all three "healthy" endpoints, so roughly 2/3 of requests hit dead ports.

**Why stale entries survive after a job stop:** Nomad-registered Connect
sidecar-proxy services can remain in Consul's catalog, still reporting
"passing", long after the underlying alloc stops — if the Consul agent on
that node was restarted/rebuilt in between, its anti-entropy loop only
reconciles services **its own current local state** knows about. It has no
record of ever having created the stale entries, so it never proactively
removes them.

**Fix — restart the backend, then deregister the stale entries via the
catalog API (works from any agent, unlike the agent-local endpoint):**

```bash
# 1. Bring the backend back up
nomad job run nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl

# 2. Deregister stale entries directly via the catalog API (any agent can do this)
curl -X PUT "$CONSUL_HTTP_ADDR/v1/catalog/deregister" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  -d '{"Node":"<node-name>","ServiceID":"<stale-service-id>"}'
```

Note: `/v1/agent/service/deregister/<id>` (the agent-local endpoint) returns
`Unknown service ID` if the ID isn't in that specific agent's *current*
state — it will NOT work for entries orphaned by an agent restart, even
though `/v1/health/service/...` shows them attached to that node. Use
`/v1/catalog/deregister` instead, which talks to the servers directly.

After restarting `countdash-mesh` and deregistering the two stale entries,
5/5 consecutive requests through the gateway returned `HTTP 200` with the
actual `countdash-web` page.

**Takeaway for future sessions:** when a mesh backend intermittently returns
503/connection-refused through an otherwise-healthy gateway, check `nomad job
status <backend-job>` first — it may simply be stopped, and/or the catalog
may hold stale sidecar-proxy entries from before it was stopped.

## 5. `Missing: nomad.var.block(...)` — no Nomad ACL policy grants the gateway task read access to its own variable

Hit while rebuilding the gateway job from scratch (`nomad var put` +
`nomad job run -namespace ingress api-gateway.nomad.hcl`) on a cluster
where the gateway had previously been torn down. The `gateway` task's
`template { {{- with nomadVar "nomad/jobs/api-gateway/gateway/setup" -}} }`
block never resolved — `nomad alloc status` showed the task stuck
`pending` with:

```text
Missing: nomad.var.block(nomad/jobs/api-gateway/gateway/setup@ingress.global)
```

The variable itself existed (`nomad var get -namespace ingress
nomad/jobs/api-gateway/gateway/setup` returned it fine with the
bootstrap/management token) — the problem is the **task's own workload
identity** has no read grant for it. Nomad's implicit per-task variable
access only auto-covers the exact path `nomad/jobs/<job>/<group>/<task>`;
this variable's path (`.../gateway/setup`) doesn't match that pattern (the
task is named `gateway`, but the path's last segment is `setup`), and
`nomad acl policy list` showed **zero** policies on this cluster — nothing
was ever created to grant this access explicitly.

**Fix — a workload-associated Nomad ACL policy scoped to exactly this
job/group/task:**

```bash
cat > /tmp/api-gateway-variables-policy.hcl <<'EOF'
namespace "ingress" {
  variables {
    path "nomad/jobs/api-gateway/gateway/*" {
      capabilities = ["read"]
    }
  }
}
EOF

nomad acl policy apply -namespace ingress -job api-gateway -group gateway -task gateway \
  api-gateway-variables /tmp/api-gateway-variables-policy.hcl
```

No task restart needed — the template resolved within seconds of applying
the policy (Nomad's variable-read check is evaluated per-request against
the task's current workload identity claims, not baked in at task start).

**Takeaway:** this is a one-time **cluster ACL state** fact, not something
`api-gateway.nomad.hcl` creates itself. It's since been folded into
`ansible/playbooks/consul_nomad_service_mesh.yaml` Play 4 (which already
created the `ingress` namespace and the Consul-side API Gateway binding
rule, and now also applies this policy) as part of
[transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md)'s
"make transparent proxy the default" work — live-reverified by deleting the
policy and re-running the playbook, which recreated it automatically with no
manual `nomad acl policy apply` needed.

## 6. Same 503 symptom as issue 4, different root cause: local `consul` CLI/server version skew

Hit while re-verifying the gateway from scratch (deleting and rewriting
`gateway-listener.hcl` / `http-route-countdash.hcl` via `consul config
write`) during the transparent-proxy-default automation pass. Symptom looked
identical to issue 4 (503, otherwise-healthy-looking gateway) but every
diagnostic that ruled things out for issue 4 also ruled them out here:
intentions allowed, config entries "Accepted"/"Bound", exactly one healthy
`countdash-web` catalog registration (no duplicates), Consul server logs
showed zero errors or warnings. A `nomad job restart -task gateway` did
**not** fix it, nor did deleting and rewriting the config entries again —
both produced the exact same broken state deterministically.

**Diagnosis:** Envoy's admin API (`/config_dump?resource=dynamic_route_configs`
vs. `/clusters`) showed a genuine RDS/CDS name mismatch — the CDS cluster was
named `1a47f6e1~countdash-web.default.dc1.internal.<trust-domain>.consul`
(hash-prefixed, healthy, one endpoint), but the RDS route's target cluster
was `countdash-web.default.dc1.internal.<trust-domain>.consul` — the same
name **without** the hash prefix, so every request failed Envoy's cluster
lookup (`no_cluster` stat incrementing on every request). Since this
survived a clean config-entry recreate, it wasn't a one-off xDS sync race —
something was consistently generating mismatched xDS resources.

**Root cause:** `consul version` locally reported `v2.0.2`, while the
cluster's actual Consul agents run `v2.0.2` (confirmed via `ssh
<server> consul version`, since the *server's own* installed CLI is
guaranteed to match the agent it's colocated with). Homebrew had silently
upgraded the local `consul` CLI mid-session. The mismatched local CLI
encodes `http-route` config entries with newer schema fields (e.g. an
explicit `Filters.ExtProc`/`Filters.ExtAuthz` structure) — writing directly
confirmed this: the same file that had applied cleanly earlier in the
session started failing with `invalid config key "Rules[0].Filters.ExtProc"`
once the local CLI silently became newer than the server. Even where the
write nominally succeeded (no rejected keys), the encoding skew was still
enough to desync how the server's API Gateway controller derived the RDS
route name from the CDS cluster name it generated for the same config.

**Fix:** write config entries using a `consul` binary that matches the
**server's** version, not whatever happens to be on the local machine's
`PATH`. Easiest way: `scp` the `.hcl` file to a server and run `consul
config write` there over SSH, using the server's own locally-installed
binary and `127.0.0.1` as the address:

```bash
scp -i ssh_key.pem gateway-listener.hcl http-route-countdash.hcl \
  ubuntu@<server-ip>:/tmp/
ssh -i ssh_key.pem ubuntu@<server-ip> '
  export CONSUL_HTTP_ADDR=https://127.0.0.1:8443
  export CONSUL_HTTP_TOKEN=$(cat /tmp/consul-bootstrap-secret-id.txt)
  export CONSUL_CACERT=/tmp/ca.pem
  consul config write /tmp/gateway-listener.hcl
  consul config write /tmp/http-route-countdash.hcl
'
```

Rewriting the same two config entries this way (byte-identical `.hcl`
content, only the CLI binary changed) immediately fixed the route/cluster
mismatch — 10/10 subsequent requests returned `HTTP 200`.

**Takeaway:** don't assume a local CLI's reported version matches a remote
cluster's actual version, especially in a long session — package managers
can upgrade a binary out from under you mid-session with no prompt. When a
`consul config write` (or `nomad job run`, etc.) behaves inconsistently
with no server-side error explaining why, check `consul version` (or
equivalent) against the actual server/agent version before assuming the
config content itself is wrong. This is a general risk for any long-lived
session using local CLI tools against a persistent remote cluster, not
specific to API Gateway.

**Update — CLI version skew is a trigger, not the only cause.** Hit the
identical `no_cluster` RDS/CDS-mismatch symptom again later (adding a
second gateway listener for
[dedicated-ingress-node-plan.md](dedicated-ingress-node-plan.md)'s
simultaneous Countdash+HashiCups access), this time with local and server
`consul` CLI versions already matching (`v2.0.2` on both). Writing the
config from the server didn't fix it by itself. What did: **deleting**
(not just overwriting) the `http-route` and `api-gateway` config entries,
recreating them, and then a full `nomad job stop -purge` +
`nomad job run` of the gateway job (not just `nomad job restart -task`,
which also didn't fix it). This points to a genuine staleness/race in
Consul API Gateway v2's own xDS controller — when its config entries are
rewritten while a gateway allocation's Envoy already holds an open xDS
stream, the controller can persistently (not just momentarily) serve a
route referencing a stale, unprefixed cluster name instead of the
freshly-generated hash-prefixed one. CLI version skew is *one* way to
trigger a bad write that leads here, but matching versions doesn't
guarantee immunity. If this recurs: delete+recreate the config entries
*and* fully stop+purge+redeploy the gateway job (both together — neither
alone was sufficient during this session), then check
`/config_dump?resource=dynamic_route_configs` vs `/clusters` again to
confirm the route and cluster names actually match before retesting.

## Useful commands referenced above

```bash
# Dump Envoy's generated bootstrap without execing it (diagnose TLS/xDS issues)
consul connect envoy -gateway=api -register -service api-gateway \
  -address '...' -bootstrap > /alloc/bootstrap.json

# /dev/tcp workaround for containers with no curl/wget/nc (e.g. envoyproxy/envoy images)
exec 3<>/dev/tcp/127.0.0.1/19000
printf 'GET /clusters HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n' >&3
cat <&3   # must be HTTP/1.1 with Connection: close — HTTP/1.0 gets 426 Upgrade Required

# Find stale/duplicate sidecar-proxy registrations
curl -sk -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "$CONSUL_HTTP_ADDR/v1/health/service/countdash-web-sidecar-proxy?passing"

# Deregister a stale catalog entry (works from any agent)
curl -X PUT "$CONSUL_HTTP_ADDR/v1/catalog/deregister" \
  -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  -d '{"Node":"<node-name>","ServiceID":"<service-id>"}'
```
