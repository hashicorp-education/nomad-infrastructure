# Consul API Gateway: Envoy bootstrap failures and stale mesh registrations

Four linked issues found while getting `nomad-jobs/consul-mesh/api-gateway.nomad.hcl`
(rollout step 6 of [consul-service-mesh-plan.md](consul-service-mesh-plan.md))
to a genuinely healthy, end-to-end-working state — not just "deployment
successful" in Nomad, but an actual HTTPS request proxied through to a mesh
backend. The first three are gateway job bugs; the fourth is a Consul catalog
hygiene issue unrelated to the gateway itself, included here because its
symptom (503 from a healthy-looking gateway) is easy to misattribute back to
the gateway.

## 1. `hashicorp/consul` images do not bundle `envoy`

`consul connect envoy -gateway=api -register` needs both the `consul` and
`envoy` binaries in the same container. `hashicorp/consul:2.0.1` does not
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
the `hashicorp/consul:2.0.1` image copies the binary into the shared `alloc/`
directory:

```hcl
task "fetch-consul" {
  driver = "docker"
  lifecycle {
    hook    = "prestart"
    sidecar = false
  }
  config {
    image      = "hashicorp/consul:2.0.1"
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
nomad job run nomad-jobs/consul-mesh/countdash-consul-service-mesh.nomad.hcl

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
