# HashiCups Nomad Job

This directory contains the Nomad job specification for deploying **HashiCups**,
a coffee shop demo application, using Consul service discovery. The job
demonstrates multi-node scheduling: each of the six services runs in its own
Nomad group, which lets the scheduler place them on different client nodes.
Services discover each other using Consul DNS names.

A service mesh variant, [`hashicups-consul-service-mesh.nomad.hcl`](hashicups-consul-service-mesh.nomad.hcl),
runs all six services with `network.mode = "bridge"` and Envoy Connect
sidecar proxies instead of plain Consul DNS discovery, fronted by the Consul
API Gateway. See [`nomad-jobs/consul-mesh/README.md`](../consul-mesh/README.md)
for the full deploy order.

## Prerequisites

This job requires a running Consul + Nomad cluster with dnsmasq configured.
Deploy the cluster using one of these options:

```bash
cd ansible
# Option C — Consul + Nomad + service discovery (recommended)
ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml

# Option D — Consul + Nomad + service discovery + workload identity
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml

# Option E — Consul + Nomad + service discovery + workload identity + service mesh
# (required for hashicups-consul-service-mesh.nomad.hcl)
ansible-playbook -i inventory.ini deploy_consul_nomad_mesh.yaml
```

After the playbook completes, source the environment variables:

```bash
source ./set-cluster-env.sh
```

Refer to the [Nomad plus Consul cluster deployment
guide](../../DEPLOY_CLUSTER_GUIDE.md) for detailed cluster deployment instructions.


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
nginx task  ──► registers attr.unique.platform.aws.public-hostname
    │
    ├──► /api  ──► public-api.service.dc1.global:8081  (VPC-internal)
    │                   │
    │                   ├──► product-api.service.dc1.global:9090
    │                   │           │
    │                   │           └──► database.service.dc1.global:5432
    │                   │
    │                   └──► payments-api.service.dc1.global:8080
    │
    └──► /    ──► frontend.service.dc1.global:3000  (VPC-internal)
```

nginx is the only service that registers its public hostname. All backend
services register their private IPv4 address (`attr.unique.platform.aws.local-ipv4`)
and are reachable only within the VPC.

### HTTPS (self-signed certificate)

The `nginx` group runs a `prestart` task, `nginx-tls-init`, before the `nginx`
task starts. It generates a fresh self-signed certificate and key with
`openssl` into `/alloc/tls/` (the Nomad alloc directory, automatically shared
by every task in the group) using the allocation's `NOMAD_IP_nginx` address as
the certificate's SAN. nginx listens **only** on:

- `443` — HTTPS, using `/alloc/tls/nginx.crt` and `/alloc/tls/nginx.key`

There is no plain-HTTP listener — port 80 is not opened by nginx or by the
AWS security group. The Consul health check itself calls `https://.../health`
with `tls_skip_verify = true` (the cert is self-signed, so certificate
validation is skipped for the health check only).

Because the certificate is self-signed and regenerated on every deploy,
browsers show a certificate warning — click through it ("Advanced" →
"Proceed") the same way you would for the Consul/Nomad UIs. This is a demo
cert, not suitable for production use.

## AWS security group requirements

Only port 443 needs an inbound rule in the AWS security group. Port 80 is
intentionally **not** opened — end users must use HTTPS. All other ports
(3000, 5432, 8080, 8081, 9090) carry VPC-internal traffic only.

| Port | Protocol | Required | Purpose |
|---|---|---|---|
| `443` | TCP | **Yes** | nginx public entry point (HTTPS, self-signed) |
| `80` | TCP | No | Not used — nginx has no HTTP listener |
| `3000` | TCP | No | frontend (VPC-internal) |
| `5432` | TCP | No | PostgreSQL (VPC-internal) |
| `8080` | TCP | No | payments-api (VPC-internal) |
| `8081` | TCP | No | public-api (VPC-internal) |
| `9090` | TCP | No | product-api (VPC-internal) |

Port 443 is not included in the default `extra_ingress_ports` list. Add it
before deploying the job using one of these methods:

**Terraform (persistent):** Edit `terraform/aws/terraform.tfvars`:

```hcl
extra_ingress_ports = [
  { port = 9002, description = "Countdash example app - web UI" },
  { port = 443,  description = "HashiCups nginx TLS" },
]
```

Then apply:

```bash
cd terraform/aws
terraform plan
terraform apply
```

**Ansible (live cluster, no `terraform apply` required):**

```bash
cd ansible
ansible-playbook playbooks/update-security-group.yaml \
  -e custom_port=443 \
  -e custom_port_description="HashiCups nginx TLS"
```

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
Because Nomad co-locates tasks within a group but schedules groups independently,
six separate allocations are created — one per service — and the scheduler can
place them on different client nodes.

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
forwards `.global` queries to the local Consul agent and all other queries to
the AWS VPC resolver.

## Per-service details

### `database` group

**Image:** `hashicorpdemoapp/product-api-db:v0.0.22`  
**Port:** 5432 (static)  
**Registers:** private IPv4

The service registers as `database` in the Consul catalog. Other services
resolve it as `database.service.dc1.global`.

**Health check:** script check runs `/usr/bin/pg_isready -d 5432` every 5
seconds with a 2-second timeout. `on_update = "ignore_warnings"` prevents
health-warning states from blocking deployments.

> **Note:** The database credentials (`POSTGRES_USER`, `POSTGRES_PASSWORD`) are
> hardcoded to `postgres` / `password` and are suitable for demo use only.

---

### `product-api` group

**Image:** `hashicorpdemoapp/product-api:v0.0.22`  
**Port:** 9090 (static)  
**Registers:** private IPv4

Connects to the database via `DB_CONNECTION`:

```
host=database.service.dc1.global port=5432 user=postgres password=password dbname=products sslmode=disable
```

**Health checks (two):**

| Name | Path | Purpose |
|---|---|---|
| `DB connection ready` | `GET /health/readyz` | Verifies the database connection is established |
| `Product API ready` | `GET /health/livez` | Verifies the HTTP server is accepting requests |

Nomad marks the allocation healthy only after both checks pass.

---

### `payments` group

**Image:** `hashicorpdemoapp/payments:v0.0.16`  
**Port:** 8080 (static)  
**Memory:** 500 MB reserved  
**Registers:** private IPv4

The Spring Boot application reads its listen port from an `application.properties`
file. The job uses a `template` block to generate that file at runtime and a
bind mount to place it in the container:

```hcl
template {
  data        = "server.port=${var.payments_api_port}"
  destination = "local/application.properties"
}
config {
  mount {
    type   = "bind"
    source = "local/application.properties"
    target = "/application.properties"
  }
}
```

**Health check:** `GET /actuator/health` (Spring Boot Actuator endpoint).

---

### `public-api` group

**Image:** `hashicorpdemoapp/public-api:v0.0.7`  
**Port:** 8081 (static)  
**Registers:** private IPv4

Acts as a GraphQL aggregator. Resolves its upstreams using Consul DNS:

```
PRODUCT_API_URI  = http://product-api.service.dc1.global:9090
PAYMENT_API_URI  = http://payments-api.service.dc1.global:8080
```

**Health check:** `GET /health`.

---

### `frontend` group

**Image:** `hashicorpdemoapp/frontend:v1.0.9`  
**Port:** 3000 (static)  
**Registers:** private IPv4

A Next.js application. `NEXT_PUBLIC_PUBLIC_API_URL="/"` routes all API
calls through nginx at `/api` so the browser never speaks directly to
`public-api`. `NEXT_PUBLIC_FOOTER_FLAG` embeds the allocation index in the
page footer, which makes it easy to identify which instance served a request
when multiple frontend allocations are running.

**Health check:** `GET /`.

---

### `nginx` group

**Image:** `nginx:alpine`  
**Port:** 443 HTTPS only (static)  
**Registers:** EC2 **public** hostname (`attr.unique.platform.aws.public-hostname`)

nginx is the public entry point and the only service that exposes a port to
the internet. The group runs two tasks:

- `nginx-tls-init` — a `prestart` task (runs to completion before `nginx`
  starts) that generates a self-signed certificate and key with `openssl`
  into `/alloc/tls/`, shared with the `nginx` task via the alloc directory.
- `nginx` — uses a Nomad `template` block to generate
  `/etc/nginx/conf.d/default.conf` at runtime with a single HTTPS `server`
  block:

| Port | Scheme | Notes |
|---|---|---|
| 443 | HTTPS | Uses the self-signed cert from `/alloc/tls/`. Only listener — there is no HTTP fallback. |

The server block defines:

- `location /` — proxies to `frontend.service.dc1.global:3000`
- `location /api` — proxies to `public-api.service.dc1.global:8081`
- `location = /health` — returns `{"status":"UP"}` as a synthetic JSON
  response so the Consul health check passes without a dedicated
  health endpoint in nginx itself

nginx resolves `frontend.service.dc1.global` and `public-api.service.dc1.global`
through dnsmasq at request time, so upstream address changes are transparent.

**Health check:** `GET https://.../health` with `tls_skip_verify = true` (the
cert is self-signed).

## Variables

All variables have defaults. Override any of them at deploy time with `-var`:

```bash
nomad job run \
  -var="nginx_tls_port=8443" \
  -var="frontend_version=v1.1.0" \
  hashicups.nomad.hcl
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

## Deploy

```bash
nomad job run hashicups.nomad.hcl
```

Nomad creates six allocations. Because the job has no node constraints, the
scheduler may place all groups on the same client node or spread them across
multiple nodes depending on available capacity:

```
nomad job allocs hashicups

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
nomad job allocs hashicups

# Verify all six services are registered in Consul
consul catalog services
```

Get the public IP (nginx can run on any client node). The following command
returns an IP address.

```bash
nomad node status -verbose \
    $(nomad job allocs hashicups | grep nginx | grep -i running | awk '{print $2}') | \
    grep -i public-ipv4 | awk -F "=" '{print $2}' | xargs
```

You may also use the Consul API to find the HashiCups public address. Before
running the following command, export `CONSUL_HTTP_ADDR` and
`CONSUL_HTTP_TOKEN`. Run `source ansible/set-cluster-env.sh` from the repository
root if you have not already done so. The command also requires [curl
v8.3.0+](https://curl.se/) and [jq](https://jqlang.org/).

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

Plain HTTP is not available — nginx has no port 80 listener, and the AWS
security group does not open port 80. Expect a browser certificate warning
since the cert is self-signed and regenerated on every deploy — click through
it ("Advanced" → "Proceed"), the same as for the Consul/Nomad UIs.

## Clean up

```bash
nomad job stop -purge hashicups
```
