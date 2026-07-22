# HashiCups — Multipass (Consul Service Discovery)

This is the Multipass-portable variant of the Nomad job specification for
deploying **HashiCups**, a coffee shop demo application, using Consul
service discovery ([`hashicups-multipass.nomad.hcl`](hashicups-multipass.nomad.hcl)).
Like [`hashicups.nomad.hcl`](hashicups.nomad.hcl) (the AWS-only variant —
see [`README-hashicups.md`](README-hashicups.md)), the job demonstrates
multi-node scheduling: each of the six services runs in its own Nomad group,
letting the scheduler place them on different client nodes, and services
discover each other using Consul DNS names.

The only differences from the AWS variant:

1. **Node attributes**: every group's `service.address` uses
   `attr.unique.network.ip-address` (the platform-agnostic node attribute
   Nomad fingerprints on every host — AWS, Multipass, bare metal) instead of
   the AWS-only `attr.unique.platform.aws.local-ipv4` / `.public-hostname`.
   This is what makes the file portable — everything else is identical.
2. **`nginx` group only** (the one externally-facing service) additionally
   supports registering the real EC2 public hostname when actually deployed
   to AWS — see "Traffic flow" below.
3. **Job name**: `hashicups-multipass`, not `hashicups` — so this and the
   AWS variant can be deployed to the same cluster at once without one
   overwriting the other via an in-place job update. (Both files originally
   declared `job "hashicups"` — the same job-ID collision bug found and
   fixed for the Countdash job specs; see
   [`_context/wiki/countdash-job-id-collision-and-multiarch.md`](../../_context/wiki/countdash-job-id-collision-and-multiarch.md).)

Because this file works on both platforms, **this is the variant to deploy
by default** — reach for `hashicups.nomad.hcl` only if you specifically want
the AWS-only version for some reason.

## Prerequisites

This job requires a running Consul + Nomad cluster with dnsmasq configured
— on Multipass (`terraform/multipass/`) or AWS (`terraform/aws/`), same
Ansible playbooks either way:

```bash
cd ansible
# Option C — Consul + Nomad + service discovery (recommended)
ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml

# Option D — Consul + Nomad + service discovery + workload identity
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml
```

After the playbook completes, source the environment variables — this is
required, not optional, for this job spec specifically, since it also
detects and exports which platform you're on:

```bash
source ./set-cluster-env.sh
```

Refer to the [Nomad plus Consul cluster deployment
guide](../../DEPLOY_CLUSTER_GUIDE.md) for detailed cluster deployment
instructions, and
[`_context/wiki/multipass-local-testing-plan.md`](../../_context/wiki/multipass-local-testing-plan.md)
for the Multipass workspace specifically.

## Application architecture

HashiCups is composed of six services. The job deploys each service in its own
Nomad group.

| Service | Image | Default port | Upstream dependencies |
|---|---|---|---|
| `database` | `hashicorpdemoapp/product-api-db` | 5432 | None |
| `payments-api` | `hashicorpdemoapp/payments` | 8080 | None |
| `product-api` | `hashicorpdemoapp/product-api` | 9090 | `database` |
| `public-api` | `hashicorpdemoapp/public-api` | 8081 | `product-api`, `payments-api` |
| `frontend` | `hashicorpdemoapp/frontend` | 3000 | None (served through nginx) |
| `nginx` | `nginx:alpine` | 443 (HTTPS only) | `frontend`, `public-api` |

### Traffic flow

```
Browser (your machine)
    │
    │  port 443 (HTTPS, self-signed cert)
    ▼
nginx task  ──► registers attr.unique.network.ip-address
                (or attr.unique.platform.aws.public-hostname on AWS -
                 see below, detected automatically)
    │
    ├──► /api  ──► public-api.service.dc1.global:8081  (internal)
    │                   │
    │                   ├──► product-api.service.dc1.global:9090
    │                   │           │
    │                   │           └──► database.service.dc1.global:5432
    │                   │
    │                   └──► payments-api.service.dc1.global:8080
    │
    └──► /    ──► frontend.service.dc1.global:3000  (internal)
```

All backend services register `attr.unique.network.ip-address` (internal
only — Multipass's bridged VM IP, or AWS's private IP) and are reachable
only within the cluster's own network.

**`nginx` is the only service that ever needs to be externally reachable**,
and it uses a `deployment_platform` job variable to pick the right address
for whichever network it's actually on:

- `deployment_platform = "generic"` (the default) → registers
  `attr.unique.network.ip-address`. Correct on Multipass, where this is
  already the address reachable from your Mac's browser (no public/private
  split).
- `deployment_platform = "aws"` → registers
  `attr.unique.platform.aws.public-hostname` instead, since on AWS the
  platform-agnostic attribute resolves to the *private* IP, which isn't
  reachable from outside the VPC.

You do not need to pass `-var` for this — source
[`ansible/set-cluster-env.sh`](../../ansible/set-cluster-env.sh) first (see
Prerequisites above), and it detects the platform from
`ansible/inventory.ini` and exports `NOMAD_VAR_deployment_platform`
automatically. Nomad's CLI reads `NOMAD_VAR_<name>` exactly like
`-var <name>=value`.

**Sharp edge, confirmed by live testing**: each *branch* of this ternary is
resolved per-node, at runtime. If `NOMAD_VAR_deployment_platform` somehow
doesn't match the platform you're actually deploying to (`set-cluster-env.sh`
wasn't sourced, or `inventory.ini` is stale), Nomad does not error — it
silently registers the literal unresolved text
`${attr.unique.platform.aws.public-hostname}` as the service address, which
then fails the `nginx` health check trying to parse that literal text as a
URL (`invalid URL escape "%7B"` in the check output). If you see that exact
error, `NOMAD_VAR_deployment_platform` doesn't match reality — re-source
`set-cluster-env.sh`, don't edit the job spec. Full write-up, including why
this needs a variable at all instead of being fully automatic via Nomad node
metadata (tried first, proven not to work), in
[`_context/wiki/deployment-platform-auto-detection.md`](../../_context/wiki/deployment-platform-auto-detection.md).

### HTTPS (self-signed certificate)

The `nginx` group runs a `prestart` task, `nginx-tls-init`, before the `nginx`
task starts. It generates a fresh self-signed certificate and key with
`openssl` into `/alloc/tls/` (the Nomad alloc directory, automatically shared
by every task in the group) using the allocation's `NOMAD_IP_nginx` address as
the certificate's SAN. nginx listens **only** on:

- `443` — HTTPS, using `/alloc/tls/nginx.crt` and `/alloc/tls/nginx.key`

There is no plain-HTTP listener — port 80 is not opened by nginx. The Consul
health check itself calls `https://.../health` with
`tls_skip_verify = true` (the cert is self-signed, so certificate validation
is skipped for the health check only).

Because the certificate is self-signed and regenerated on every deploy,
browsers show a certificate warning — click through it ("Advanced" →
"Proceed") the same way you would for the Consul/Nomad UIs. This is a demo
cert, not suitable for production use.

## Networking requirements

**Multipass**: no security groups to configure — Multipass VMs are on a
shared bridge network already reachable from your Mac; just make sure
nothing else on your machine is using port 443 locally.

**AWS**: if you deploy this file to AWS (with `deployment_platform=aws`),
the same port 443 ingress rule documented in
[`README-hashicups.md`'s "AWS security group requirements"](README-hashicups.md#aws-security-group-requirements)
applies — this job's `nginx` group is identical to the AWS-only variant's.

## Consul configuration required

| Requirement | Details |
|---|---|
| Consul agents | Running on all nodes (deployed by `consul_servers.yaml` and `consul_clients.yaml`) |
| dnsmasq | Running on all nodes, forwarding `.global` queries from `172.17.0.1` to Consul port 8600 (deployed by `dnsmasq.yaml`) |
| Consul domain | `global` — matches the `.service.dc1.global` suffix in all DNS names |
| Consul datacenter | `dc1` — matches the datacenter component of all DNS names |
| Consul ACLs | DNS token applied to every Consul agent so service lookups succeed (deployed by `consul_dns_token.yaml`) |

All of these are configured automatically by `deploy_consul_nomad_sd.yaml`.

## Job structure

The job uses `type = "service"` and places each service in a separate group.
Because Nomad co-locates tasks within a group but schedules groups
independently, six separate allocations are created — one per service — and
the scheduler can place them on different client nodes.

### DNS in Docker containers

Every `network` block includes:

```hcl
dns {
  servers = ["172.17.0.1"]
}
```

This passes `--dns 172.17.0.1` to Docker, directing containers to send DNS
queries to dnsmasq on the Docker bridge gateway rather than to `127.0.0.1`
(which resolves to the container's own loopback, not the host). dnsmasq
forwards `.global` queries to the local Consul agent and all other queries
to the upstream resolver (the AWS VPC resolver on AWS; public resolvers on
Multipass, per `dnsmasq_upstream_dns_servers` in `ansible/inventory.ini`).

## Per-service details

Identical to the AWS variant except for the `address` field noted per
group — full per-service breakdown (health checks, images, upstream
connection strings) in
[`README-hashicups.md`'s "Per-service details"](README-hashicups.md#per-service-details).

| Group | Registers |
|---|---|
| `database` | `attr.unique.network.ip-address` |
| `product-api` | `attr.unique.network.ip-address` |
| `payments` | `attr.unique.network.ip-address` |
| `public-api` | `attr.unique.network.ip-address` |
| `frontend` | `attr.unique.network.ip-address` |
| `nginx` | `attr.unique.network.ip-address` (default) or the AWS public hostname (`deployment_platform=aws`) — see "Traffic flow" above |

## Variables

All variables have defaults. Override any of them at deploy time with `-var`:

```bash
nomad job run \
  -var="nginx_tls_port=8443" \
  -var="frontend_version=v1.1.0" \
  hashicups-multipass.nomad.hcl
```

| Variable | Default | Description |
|---|---|---|
| `datacenters` | `["*"]` | Datacenters eligible for task placement |
| `region` | `global` | Nomad region |
| `frontend_version` | `v1.0.9` | Docker image tag for frontend |
| `public_api_version` | `v0.0.7` | Docker image tag for public-api |
| `payments_version` | `v0.0.16` | Docker image tag for payments |
| `product_api_version` | `v0.0.22` | Docker image tag for product-api |
| `product_api_db_version` | `v0.0.22` | Docker image tag for database |
| `postgres_db` | `products` | PostgreSQL database name |
| `postgres_user` | `postgres` | PostgreSQL username |
| `postgres_password` | `password` | PostgreSQL password |
| `db_port` | `5432` | PostgreSQL port |
| `product_api_port` | `9090` | product-api port |
| `payments_api_port` | `8080` | payments-api port |
| `public_api_port` | `8081` | public-api port |
| `frontend_port` | `3000` | frontend port |
| `nginx_tls_port` | `443` | nginx public HTTPS port (only listener) |
| `deployment_platform` | `generic` | Selects which node attribute `nginx` registers its address as. Set automatically by `ansible/set-cluster-env.sh` — see "Traffic flow" above |

## Deploy

```bash
source ansible/set-cluster-env.sh   # from the repo root; exports NOMAD_VAR_deployment_platform
nomad job run hashicups-multipass.nomad.hcl
```

Nomad creates six allocations. Because the job has no node constraints, the
scheduler may place all groups on the same client node or spread them across
multiple nodes depending on available capacity:

```
nomad job allocs hashicups-multipass

ID        Node ID   Task Group   Version  Desired  Status   Created  Modified
2f680e43  c131bce2  db           0        run      running  ...
4a3f2e8b  c131bce2  nginx        0        run      running  ...
6512bee8  c131bce2  payments     0        run      running  ...
7190a16a  c131bce2  frontend     0        run      running  ...
a67f6273  c131bce2  public-api   0        run      running  ...
c83120cc  c131bce2  product-api  0        run      running  ...
```

## Verify

```bash
# Check allocation status
nomad job allocs hashicups-multipass

# Verify all six services are registered in Consul
consul catalog services
```

Use the Consul API to find HashiCups' address (works whether `nginx`
registered a private IP or a public hostname). Before running the following
command, export `CONSUL_HTTP_ADDR` and `CONSUL_HTTP_TOKEN` — run
`source ansible/set-cluster-env.sh` from the repository root if you have not
already done so. The command also requires
[curl v8.3.0+](https://curl.se/) and [jq](https://jqlang.org/).

```bash
curl --cacert "$CONSUL_CACERT" --variable '%CONSUL_HTTP_ADDR' --variable '%CONSUL_HTTP_TOKEN' \
  --expand-url "{{CONSUL_HTTP_ADDR}}/v1/catalog/service/nginx?passing" \
  --expand-header "X-Consul-Token: {{CONSUL_HTTP_TOKEN}}" \
  | jq -r '.[] | .ServiceAddress'
```

The result is the bare address. Access HashiCups over HTTPS only:

```bash
https://<ServiceAddress>      # HTTPS, port 443, self-signed certificate
```

Plain HTTP is not available — nginx has no port 80 listener. Expect a
browser certificate warning since the cert is self-signed and regenerated
on every deploy — click through it ("Advanced" → "Proceed"), the same as
for the Consul/Nomad UIs.

## Clean up

```bash
nomad job stop -purge hashicups-multipass
```
