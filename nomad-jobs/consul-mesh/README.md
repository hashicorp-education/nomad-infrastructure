# Consul service mesh — config entries and API Gateway

This directory contains Consul config entries, the Nomad API Gateway job, and
the mesh-enabled Countdash and HashiCups job specs for the **Option E**
service mesh deployment. The non-mesh variants of Countdash and HashiCups
live in [`../consul-sd/`](../consul-sd/) and [`../nomad-sd/`](../nomad-sd/),
each with their own job-specific README.

## Prerequisites

The cluster must already be deployed with [Option E (service mesh)](../../DEPLOY_CLUSTER_GUIDE.md).

Verify Consul service mesh (Consul Connect) is active on all Nomad clients before continuing:

```bash
nomad node status -verbose \
  $(nomad node status -short | grep ready | awk '{print $1}') \
  | grep consul.connect
# consul.connect = true  (must appear for every client node)
```

The API Gateway job always schedules onto a dedicated public ingress Nomad
client — see [Viewing the app in your web
browser](#viewing-the-app-in-your-web-browser) below and
[`_context/wiki/dedicated-ingress-node-plan.md`](../../_context/wiki/dedicated-ingress-node-plan.md).
On AWS, ports 8447/8448 are opened automatically on that node's security
group by Terraform (`aws_security_group.ingress_sg`) — no manual step
needed here. On Multipass there is no security-group equivalent, so this
step doesn't apply at all — every VM's ports are already reachable from the
host once `ingress_client_count = 1` provisions the node.

Confirm the ingress client exists and is tagged before continuing:

```bash
nomad node status -verbose \
  $(nomad node status -short | grep ready | awk '{print $1}') \
  | grep nodeRole
# meta.nodeRole = ingress   (must appear for exactly one client node)
```

> **Shortcut:** `ansible-playbook -i inventory.ini playbooks/consul_nomad_api_gateway.yaml`
> automates steps 1, 2, 3, 4, 5, 6, and 8 below for Countdash in one run
> (service-defaults, intentions, self-signed gateway cert + inline-certificate
> config entry, gateway listener, the countdash http-route, the Nomad
> variable, and the API Gateway job itself). It does **not** deploy step 7
> (the countdash-mesh-tproxy job itself) or step 9 (HashiCups) — do those
> manually as shown below. Read on if you want to understand or run each
> step individually (e.g. for HashiCups, or to customize the gateway cert).

## Deploy order

Follow this order exactly. Each step depends on the previous one.

### 1. Apply service-defaults

`service-defaults` config entries tell Consul which protocol each service
speaks. The API Gateway requires `http` on every destination service it routes
to. PostgreSQL must use `tcp`.

```bash
# Countdash (already applied in Step 4 of the rollout, repeated here for completeness)
consul config write service-defaults/countdash-api.hcl
consul config write service-defaults/countdash-web.hcl

# HashiCups
consul config write service-defaults/nginx.hcl
consul config write service-defaults/frontend.hcl
consul config write service-defaults/public-api.hcl
consul config write service-defaults/product-api.hcl
consul config write service-defaults/payments-api.hcl
consul config write service-defaults/database.hcl
```

Verify:

```bash
consul config list -kind service-defaults
```

### 2. Apply service intentions

One `service-intentions` file per **destination** service. Every unlisted
source→destination pair is denied (Consul default-deny ACL policy).

```bash
# Countdash (already applied in Step 5 of the rollout)
consul config write intentions/countdash-api.hcl
consul config write intentions/countdash-web.hcl

# HashiCups
consul config write intentions/nginx.hcl
consul config write intentions/frontend.hcl
consul config write intentions/public-api.hcl
consul config write intentions/product-api.hcl
consul config write intentions/payments-api.hcl
consul config write intentions/database.hcl
```

Verify a specific path:

```bash
consul intention check api-gateway nginx    # Allowed
consul intention check nginx database       # Denied (not in intentions)
```

### 3. Generate the gateway TLS certificate and apply the inline-certificate config entry

The API Gateway terminates HTTPS. It needs a certificate that the browser will
accept (or click through for a self-signed cert). Generate and apply in one
pipeline — never commit cert/key material to the repo:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /tmp/gateway.key \
  -out /tmp/gateway.crt \
  -days 365 \
  -subj "/CN=api-gateway.local" \
  -addext "subjectAltName=IP:<public_ip_of_the_ingress_client>"
# Look up the ingress client's IP: terraform output client_public_ips_by_node
# (the nomad-ingress-client-N entry) — the gateway only ever runs there.

consul config write - <<EOF
Kind        = "inline-certificate"
Name        = "api-gateway-cert"
Certificate = "$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' /tmp/gateway.crt)"
PrivateKey  = "$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' /tmp/gateway.key)"
EOF
```

Verify:

```bash
consul config read -kind inline-certificate -name api-gateway-cert
```

### 4. Apply the api-gateway listener config entry

```bash
consul config write gateway-listener.hcl
```

This registers the `api-gateway` config entry with **two** HTTPS listeners,
both referencing the `api-gateway-cert` inline-certificate: `https-countdash`
on port `8447` and `https-hashicups` on port `8448`. Each app gets its own
port instead of sharing one path-based route — see [Viewing the app in your
web browser](#viewing-the-app-in-your-web-browser) below and
[`_context/wiki/dedicated-ingress-node-plan.md`](../../_context/wiki/dedicated-ingress-node-plan.md).

### 5. Apply http-routes

```bash
consul config write http-route-countdash.hcl
consul config write http-route-hashicups.hcl
```

Each route binds to its own listener (`http-route-countdash.hcl` →
`https-countdash`/8447, `http-route-hashicups.hcl` → `https-hashicups`/8448),
so both can be applied — and both apps reached — at the same time; there's
no "only one active route" caveat to work around anymore.

### 6. Store the Consul CA cert as a Nomad variable

The API Gateway job reads the Consul CA cert from a Nomad variable so it can
trust the cluster's self-signed TLS certificate:

```bash
nomad var put -namespace ingress \
  nomad/jobs/api-gateway/gateway/setup \
  consul_cacert=@ansible/.tls/ca.pem
```

Verify:

```bash
nomad var get -namespace ingress nomad/jobs/api-gateway/gateway/setup
```

### 7. Deploy and verify the countdash mesh job (transparent proxy — default)

**Live-verified end-to-end on a real AWS cluster** — see
[`_context/wiki/transparent-proxy-enablement-plan.md`](../../_context/wiki/transparent-proxy-enablement-plan.md)
for the full rollout and the bugs found/fixed along the way.

`countdash-transparent-proxy.nomad.hcl` is the default/recommended Countdash
mesh job: the countdash-web → countdash-api hop uses Consul's
`transparent_proxy` instead of an explicit `upstreams` block, so
countdash-web calls Consul's **virtual-IP** DNS name
(`countdash-api.virtual.global` — *not* the classic
`countdash-api.service.dc1.global` name used elsewhere in this repo; see the
enablement-plan page's Bug 3) instead of a fixed `127.0.0.1` port. See
[`_context/wiki/transparent-proxy-vs-upstreams.md`](../../_context/wiki/transparent-proxy-vs-upstreams.md)
for why this is the recommended default over explicit `upstreams`.

Requires the `consul-cni` CNI plugin on Nomad clients — already installed by
`consul_nomad_service_mesh.yaml` Play 2 (`consul_cni_enabled: true`) as part
of the mesh-enabling playbook you already ran above; no separate step:

```bash
nomad job run nomad-jobs/consul-mesh/countdash-transparent-proxy.nomad.hcl
nomad job status countdash-mesh-tproxy
# Wait until all allocs are "running" with a connect-proxy-* sidecar task
```

Check sidecar logs for bootstrap errors:

```bash
nomad alloc logs -task connect-proxy-countdash-web \
  $(nomad job allocs countdash-mesh-tproxy | grep countdash-web | grep running | awk '{print $1}')
```

### 7b. Optional: explicit `upstreams` variant of Countdash

`countdash-upstreams.nomad.hcl` is the alternative to Step 7 — same app,
but countdash-web reaches countdash-api through an explicit
`connect.sidecar_service.proxy.upstreams` block bound to a fixed
`127.0.0.1:<port>`, instead of `transparent_proxy`. No `consul-cni`
dependency. See
[`_context/wiki/transparent-proxy-vs-upstreams.md`](../../_context/wiki/transparent-proxy-vs-upstreams.md)
for the tradeoffs (every dependency spelled out in the job spec vs. no app
rewiring needed).

```bash
nomad job run nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl
nomad job status countdash-mesh-upstreams
```

Uses the same service-defaults and intentions as Step 1/2 above
(`countdash-api`, `countdash-web`) — no new Consul config entries needed.
Run alongside (not instead of) `countdash-mesh-tproxy` if you want to
compare both — they're independent jobs with independent job IDs.

### 8. Deploy the API Gateway job

```bash
nomad job run -namespace ingress nomad-jobs/consul-mesh/api-gateway.nomad.hcl
nomad job status -namespace ingress api-gateway
```

Check gateway task logs:

```bash
nomad alloc logs -namespace ingress -task gateway \
  $(nomad job allocs -namespace ingress api-gateway | grep running | awk '{print $1}')
```

Verify the gateway is reachable (replace `<IP>` with the ingress client's
public IP — see [Viewing the app in your web
browser](#viewing-the-app-in-your-web-browser) for how to find it):

```bash
curl -k https://<IP>:8447/
# Should return the countdash-web UI (HTML response)
```

### 9. Deploy the HashiCups mesh job

```bash
nomad job run nomad-jobs/consul-mesh/hashicups-consul-service-mesh.nomad.hcl
nomad job status hashicups-mesh
```

No route switching needed — `http-route-hashicups.hcl` (applied in Step 5)
is already bound to its own listener (`https-hashicups`, port `8448`), so
HashiCups comes up alongside Countdash rather than replacing it. Verify:

```bash
curl -k https://<IP>:8448/
# Should return the HashiCups nginx proxy (HTML response)
```

## Viewing the app in your web browser

Countdash and HashiCups go through the same API Gateway job, but each has
its own port — `8447` for Countdash, `8448` for HashiCups — so both are
reachable **at the same time**, in separate browser windows/tabs, with no
route-switching step. (If you only deployed one of the two apps, only its
port will actually answer — see Steps 7/7b and 9 above.)

The gateway job always runs on the same dedicated public "ingress" client
(see
[`_context/wiki/dedicated-ingress-node-plan.md`](../../_context/wiki/dedicated-ingress-node-plan.md))
— there's no need to look up which machine it happened to land on. Two
short steps:

**Step A — Look up the ingress client's public address.** Run this:

```bash
cd terraform/aws
terraform output client_public_ips_by_node
```

You'll see every client's address, keyed by name:

```text
{
  "nomad-client-1"         = "3.141.30.73"
  "nomad-client-2"         = "3.145.38.9"
  "nomad-ingress-client-1" = "3.145.100.42"
}
```

Use the `nomad-ingress-client-N` entry — that's the one the gateway always
runs on.

**Step B — Open each app in your browser**, using that same address with
the app's own port:

- Countdash: `https://<that address>:8447/` — for example,
  `https://3.145.100.42:8447/`
- HashiCups: `https://<that address>:8448/` — for example,
  `https://3.145.100.42:8448/`

Your browser will warn you that the connection isn't private or the
certificate isn't trusted, for both. That's expected, not a problem: this
cluster is using a self-signed certificate for testing, not one issued by a
recognized certificate authority, so browsers can't automatically vouch
for it. Click through the warning (in Chrome: "Advanced" → "Proceed to
... (unsafe)"; in Safari: "Show Details" → "visit this website") to
continue — once per port/tab.

## Verification checklist

- [ ] `consul config list -kind service-defaults` shows all 8 services
- [ ] `consul config list -kind service-intentions` shows all 8 destinations
- [ ] `consul config list -kind inline-certificate` shows `api-gateway-cert`
- [ ] `consul config list -kind api-gateway` shows `api-gateway`
- [ ] `consul config list -kind http-route` shows active route(s)
- [ ] `nomad var get -namespace ingress nomad/jobs/api-gateway/gateway/setup` returns the CA cert
- [ ] `nomad job status countdash-mesh-tproxy` — all allocs running with `connect-proxy-*` sidecars
- [ ] `nomad job status -namespace ingress api-gateway` — allocation running
- [ ] `curl -k https://<IP>:8447/` — HTTP 200 response (Countdash)
- [ ] `curl -k https://<IP>:8448/` — HTTP 200 response (HashiCups, if deployed)
- [ ] `consul intention check api-gateway countdash-web` — Allowed
- [ ] `consul intention check api-gateway nginx` — Allowed
- [ ] Spot-check a denied path: `consul intention check nginx database` — Denied

## Clean up

```bash
# Stop mesh jobs
nomad job stop -purge -namespace ingress api-gateway
nomad job stop -purge hashicups-mesh
nomad job stop -purge countdash-mesh-tproxy
nomad job stop -purge countdash-mesh-upstreams   # if deployed (Step 7b)

# Remove config entries
consul config delete -kind http-route -name countdash
consul config delete -kind http-route -name hashicups
consul config delete -kind api-gateway -name api-gateway
consul config delete -kind inline-certificate -name api-gateway-cert
consul config delete -kind service-intentions -name countdash-api
consul config delete -kind service-intentions -name countdash-web
consul config delete -kind service-intentions -name nginx
consul config delete -kind service-intentions -name frontend
consul config delete -kind service-intentions -name public-api
consul config delete -kind service-intentions -name product-api
consul config delete -kind service-intentions -name payments-api
consul config delete -kind service-intentions -name database
consul config delete -kind service-defaults -name countdash-api
consul config delete -kind service-defaults -name countdash-web
consul config delete -kind service-defaults -name nginx
consul config delete -kind service-defaults -name frontend
consul config delete -kind service-defaults -name public-api
consul config delete -kind service-defaults -name product-api
consul config delete -kind service-defaults -name payments-api
consul config delete -kind service-defaults -name database

# Remove the Nomad variable
nomad var purge -namespace ingress nomad/jobs/api-gateway/gateway/setup
```

## File index

| File | Kind | Description |
|---|---|---|
| `countdash-transparent-proxy.nomad.hcl` | Nomad job | Countdash, mesh-enabled with Envoy Connect sidecars and bridge networking — **default**, uses `transparent_proxy` for the countdash-web → countdash-api hop |
| `countdash-upstreams.nomad.hcl` | Nomad job | Countdash, same mesh but countdash-web → countdash-api uses an explicit `upstreams` block instead of `transparent_proxy` — alternative, no `consul-cni` dependency |
| `hashicups-consul-service-mesh.nomad.hcl` | Nomad job | HashiCups (all six groups), mesh-enabled with Envoy Connect sidecars and bridge networking |
| `gateway-listener.hcl` | `api-gateway` | Two HTTPS listeners: `https-countdash` on port 8447, `https-hashicups` on port 8448 — lets both apps be reachable simultaneously instead of sharing one path-based route |
| `inline-certificate.hcl` | instructions only | How to generate and apply the TLS cert |
| `http-route-countdash.hcl` | `http-route` | Routes the `https-countdash` listener (8447) → `countdash-web` |
| `http-route-hashicups.hcl` | `http-route` | Routes the `https-hashicups` listener (8448) → `nginx` |
| `api-gateway.nomad.hcl` | Nomad job | Envoy API Gateway in the `ingress` namespace — constrained to the dedicated public ingress client (`meta.nodeRole = "ingress"`), see [dedicated-ingress-node-plan.md](../../_context/wiki/dedicated-ingress-node-plan.md) |
| `service-defaults/` | `service-defaults` | Protocol declarations for all mesh services |
| `intentions/` | `service-intentions` | Allow-list per destination service |
