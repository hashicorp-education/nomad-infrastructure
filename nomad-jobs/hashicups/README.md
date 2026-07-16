# HashiCups Nomad Job

This directory contains the Nomad job specification for deploying **HashiCups**,
a coffee shop demo application, using Consul service discovery. The job
demonstrates multi-node scheduling: each of the six services runs in its own
Nomad group, which lets the scheduler place them on different client nodes.
Services discover each other using Consul DNS names.

## Prerequisites

This job requires a running Consul + Nomad cluster with dnsmasq configured.
Deploy the cluster using one of these options:

```bash
cd ansible
# Option C — Consul + Nomad + service discovery (recommended)
ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml

# Option D — Consul + Nomad + service discovery + workload identity
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml
```

After the playbook completes, source the environment variables:

```bash
source ./set-cluster-env.sh
```

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
| `nginx` | `nginx:alpine` | 80 | `frontend`, `public-api` |

### Traffic flow

```
Browser (your machine)
    │
    │  port 80 (TCP, public internet)
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

## AWS security group requirements

Only port 80 needs an inbound rule in the AWS security group. All other ports
(3000, 5432, 8080, 8081, 9090) carry VPC-internal traffic only.

| Port | Protocol | Required | Purpose |
|---|---|---|---|
| `80` | TCP | **Yes** | nginx public entry point |
| `3000` | TCP | No | frontend (VPC-internal) |
| `5432` | TCP | No | PostgreSQL (VPC-internal) |
| `8080` | TCP | No | payments-api (VPC-internal) |
| `8081` | TCP | No | public-api (VPC-internal) |
| `9090` | TCP | No | product-api (VPC-internal) |

Port 80 is not included in the default `extra_ingress_ports` list. Add it
before deploying the job using one of these methods:

**Terraform (persistent):** Edit `terraform/aws/terraform.tfvars`:

```hcl
extra_ingress_ports = [
  { port = 9002, description = "Countdash example app - web UI" },
  { port = 80,   description = "HashiCups nginx" },
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
ansible-playbook update-security-group.yaml \
  -e custom_port=80 \
  -e custom_port_description="HashiCups nginx"
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

### Constraints

All services except nginx must run on **private** client nodes:

```hcl
constraint {
  attribute = "${meta.nodeRole}"
  operator  = "!="
  value     = "ingress"
}
```

nginx must run on the **ingress** (public) client node so that port 80 is
reachable from the internet:

```hcl
constraint {
  attribute = "${meta.nodeRole}"
  operator  = "="
  value     = "ingress"
}
```

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
**Port:** 80 (static)  
**Registers:** EC2 **public** hostname (`attr.unique.platform.aws.public-hostname`)

nginx is the public entry point and the only service that exposes a port to
the internet. It uses a Nomad `template` block to generate
`/etc/nginx/conf.d/default.conf` at runtime:

- `location /` — proxies to `frontend.service.dc1.global:3000`
- `location /api` — proxies to `public-api.service.dc1.global:8081`
- `location = /health` — returns `{"status":"UP"}` as a synthetic JSON
  response so the Consul HTTP health check passes without a dedicated
  health endpoint in nginx itself

nginx resolves `frontend.service.dc1.global` and `public-api.service.dc1.global`
through dnsmasq at request time, so upstream address changes are transparent.

**Health check:** `GET /health`.

## Variables

All variables have defaults. Override any of them at deploy time with `-var`:

```bash
nomad job run \
  -var="nginx_port=8080" \
  -var="frontend_version=v1.1.0" \
  03.hashicups.nomad.hcl
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
| `nginx_port` | `80` | nginx public port |

## Deploy

```bash
nomad job run 03.hashicups.nomad.hcl
```

Nomad creates six allocations. The scheduler may place the non-nginx groups
across different private client nodes:

```
nomad job allocs hashicups

ID        Node ID   Task Group   Version  Desired  Status   Created  Modified
2f680e43  c131bce2  db           0        run      running  ...
4a3f2e8b  30b5f033  nginx        0        run      running  ...
6512bee8  7fb20437  payments     0        run      running  ...
7190a16a  7fb20437  frontend     0        run      running  ...
a67f6273  7fb20437  public-api   0        run      running  ...
c83120cc  7fb20437  product-api  0        run      running  ...
```

## Verify

```bash
# Check allocation status
nomad job allocs hashicups

# Verify all six services are registered in Consul
consul catalog services
```

Get the public URL (nginx runs on the ingress node):

```bash
nomad node status -verbose \
    $(nomad job allocs hashicups | grep nginx | grep -i running | awk '{print $2}') | \
    grep -i public-ipv4 | awk -F "=" '{print $2}' | xargs | \
    awk '{print "http://"$1}'
```

Use the Consul API to find the Hashicups public address. Before running the following command, complete these steps:

- Set the [post-deployment environment variables](#post-deployment-set-environment-variables)
- Installed [curl v8.3.0 or later](https://curl.se/)
- Installed [jq](https://jqlang.org/) to process the JSON response

```bash
curl --variable '%CONSUL_HTTP_ADDR' --variable '%CONSUL_HTTP_TOKEN' --expand-url "{{CONSUL_HTTP_ADDR}}/v1/catalog/service/nginx?passing" --expand-header "X-Consul-Token: {{CONSUL_HTTP_TOKEN}}"  | jq -r '.[] | "\(.ServiceAddress):\(.ServicePort)"'
```

The result displays the public URL.

Open the URL in a browser. NGINX listens on port 80, so no port number is required.

## Clean up

```bash
nomad job stop -purge hashicups
```
