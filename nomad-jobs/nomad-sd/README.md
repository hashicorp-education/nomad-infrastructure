# Countdash — Nomad Service Discovery

This directory contains [`countdash-nomad-service-discovery.nomad.hcl`](countdash-nomad-service-discovery.nomad.hcl),
one of three variants of the **Countdash** sample application — a two-tier
web app consisting of a Java Spring Boot counter API and a Go web dashboard.
This variant uses **Nomad's built-in service catalog** for service
discovery — no Consul required. The other two variants live in sibling
directories:

| File | Service discovery provider |
|------|----------------------------|
| `countdash-nomad-service-discovery.nomad.hcl` (this directory) | Nomad (built-in service catalog + template) |
| [`../consul-sd/countdash-consul-service-discovery.nomad.hcl`](../consul-sd/countdash-consul-service-discovery.nomad.hcl) | Consul (DNS lookup via dnsmasq) — see [`../consul-sd/README.md`](../consul-sd/README.md) |
| [`../consul-mesh/countdash-consul-service-mesh.nomad.hcl`](../consul-mesh/countdash-consul-service-mesh.nomad.hcl) | Consul service mesh (Envoy Connect sidecars, bridge networking) — see [`../consul-mesh/README.md`](../consul-mesh/README.md) |

## Prerequisites

A running Nomad cluster only. Unlike the other two variants, this job needs
**no Consul, no dnsmasq, and no `.global` DNS setup** — service discovery is
handled entirely by Nomad's own built-in service catalog. Any of the
`deploy_*.yaml` scenarios that stand up Nomad will work, including
`deploy_get_started.yaml` (Nomad only, no Consul at all).

## AWS security group requirements

Same as the Consul variant — see
[`../consul-sd/README.md#aws-security-group-requirements`](../consul-sd/README.md#aws-security-group-requirements)
for the full ingress rule table. Port 9002 (web UI) is included in the
default `extra_ingress_ports` list in `terraform.tfvars`; port 9001 (API) is
never opened externally.

### How traffic flows

```
Browser (your machine)
    │
    │  port 9002 (TCP, public internet)
    ▼
EC2 instance running countdash-web task  ──► address = attr.unique.network.ip-address
                                              (or attr.unique.platform.aws.public-hostname
                                               on AWS - detected automatically)
    │
    │  port 9001 (TCP, VPC-internal)
    │  address + port from Nomad's service catalog, rendered into an env var
    │  via `template` + `nomadService` at task start
    ▼
EC2 instance running countdash-api task  ──► address = attr.unique.network.ip-address
```

Both tasks register `attr.unique.network.ip-address` by default — the
platform-agnostic node attribute Nomad fingerprints on every host (AWS,
Multipass, bare metal). On AWS this resolves to the **private** IPv4 for
`countdash-web` too, unless `deployment_platform=aws` is set (see below) —
full rationale, including a documented failure mode if you get this var
wrong for the platform you're actually deploying to, in
[`../consul-sd/README.md#how-traffic-flows`](../consul-sd/README.md#how-traffic-flows)
and [`_context/wiki/deployment-platform-auto-detection.md`](../../_context/wiki/deployment-platform-auto-detection.md)
(shared across all three job specs that use this mechanism — not repeated
here). Short version: source
[`ansible/set-cluster-env.sh`](../../ansible/set-cluster-env.sh) before
running `nomad job run`, on either platform, and it's handled automatically.

## Running the job

```bash
nomad job run countdash-nomad-service-discovery.nomad.hcl
nomad job status countdash-nomad-sd
```

To run the Consul-based variant instead, see
[`../consul-sd/README.md`](../consul-sd/README.md).

Find the web app's address and port directly from Nomad's own service
catalog:

```bash
nomad service info -json countdash-web
```

The `Address` field contains the public URL, and the `Port` field contains
the port. Access the Countdash web UI at `http://<Address>:<Port>`.

Override a default port at run time:

```bash
nomad job run -var="countdash-api-port=9010" countdash-nomad-service-discovery.nomad.hcl
```

Purge the job with `nomad job stop --purge countdash-nomad-sd`.

---

## Job specification reference

The sections below walk through every stanza used in this file. The
Consul-based variant ([`../consul-sd/`](../consul-sd/)) shares most of this
structure — differences are called out inline and summarized in
["Comparison with the Consul variant"](#comparison-with-the-consul-variant)
at the end.

### `variable` blocks

```hcl
variable "countdash-api-port" {
  description = "Countdash API Port"
  default = 9001
}
```

Top-level variables set defaults that can be overridden at `nomad job run`
time with the `-var` flag. This job exposes:

| Variable | Default | Purpose |
|----------|---------|---------|
| `countdash-api-port` | `9001` | Static port bound by the API container |
| `countdash-web-port` | `9002` | Static port bound by the web container |
| `countdash-api-version` | `v3` | API image tag prefix. Combined with `${attr.cpu.arch}` at task-start time (see `config` block below) to select `hashicorpdev/counter-api:v3-amd64` or `v3-arm64` automatically |
| `countdash-web-version` | `v3` | Web image tag prefix, same `${attr.cpu.arch}` mechanism as above |
| `deployment_platform` | `generic` | Selects which node attribute `countdash-web` registers its address as (`generic` → `attr.unique.network.ip-address`, `aws` → the EC2 public hostname). Set automatically by `ansible/set-cluster-env.sh` — see ["How traffic flows"](#how-traffic-flows) above |

---

### `job` block

```hcl
job "countdash-nomad-sd" { ... }
```

The top-level `job` block names the job and contains all groups, tasks, and
configuration for the deployment. This job and the Consul-based variant use
distinct job names (`countdash-nomad-sd` / `countdash-consul-sd`)
specifically so both can be deployed to the same cluster at once without one
overwriting the other — they used to share the job name `countdash` until
this was fixed, which meant running one silently replaced the other via an
in-place job update.

---

### `group` block

```hcl
group "countdash-api" {
  count = 1
  ...
}
```

A group is a set of tasks that are co-scheduled on the same Nomad client
node. `count` controls how many instances of the group to run. This job has
two groups:

| Group | Role |
|-------|------|
| `countdash-api` | Java Spring Boot counter backend |
| `countdash-web` | Go web dashboard frontend |

---

### `network` block

```hcl
network {
  port "countdash-api" {
    static = var.countdash-api-port
  }
}
```

The `network` block is defined at the group level and controls the network
configuration for all tasks in the group.

`static` binds the container to a fixed port on the host rather than letting
Nomad assign a dynamic port. Static ports are used here because the
applications read their own port from environment variables or config
files, so they must be predictable.

Unlike the Consul-based variant, there is no `dns` stanza here — this job
never performs `.global` DNS lookups, so it needs no dnsmasq/Docker bridge
DNS routing at all.

---

### `service` block

```hcl
service {
  name     = "countdash-api"
  provider = "nomad"
  port     = "countdash-api"
  address  = attr.unique.network.ip-address
  ...
}
```

The `service` block registers the task with a service catalog so other
services can discover it.

| Field | Description |
|-------|-------------|
| `name` | Name under which the service is registered in the catalog |
| `provider` | `"nomad"` — registers with Nomad's own built-in catalog (the Consul-based variant uses `"consul"` instead; see [comparison table](#comparison-with-the-consul-variant)) |
| `port` | References the named port from the `network` block |
| `address` | Overrides the registered IP/hostname. `attr.unique.network.ip-address` is the platform-agnostic node attribute Nomad fingerprints on every host — resolves to the private IPv4 on AWS, the single bridged-network IP on Multipass. Both `countdash-api` and `countdash-web` use the same attribute (see the AWS caveat under "How traffic flows" above for what this means for the web tier specifically on AWS) |

---

### `check` block

```hcl
check {
  name      = "Countdash API ready"
  type      = "http"
  path      = "/actuator/health"
  interval  = "5s"
  timeout   = "5s"
}
```

Health checks run on the same node as the task. Nomad polls the check
endpoint on the given `interval` and marks the service unhealthy if the
check does not respond within `timeout`.

| Field | Description |
|-------|-------------|
| `type` | `"http"` sends a GET request and expects a 2xx response |
| `path` | URL path for the HTTP check |
| `interval` | How often to run the check |
| `timeout` | Maximum time to wait for a response |

---

### `check_restart` block

```hcl
check_restart {
  limit = 0
}
```

`check_restart` controls whether a failing health check triggers a task
restart. `limit = 0` disables automatic restarts on health failure — the
task stays running even if the check fails. This is set only on the API
task, where a cold JVM startup can take longer than the check timeout,
preventing premature restart loops during initialization.

---

### `task` block

```hcl
task "countdash-api" {
  driver = "docker"
  ...
}
```

A `task` is the smallest schedulable unit in Nomad. The `driver` field
selects the task driver responsible for running the workload —
`"docker"` here.

---

### `meta` block

```hcl
meta {
  service = "countdash-api"
}
```

`meta` attaches arbitrary key-value metadata to the task. These values
appear in `nomad alloc inspect` output and can be read from within the task
via the `NOMAD_META_<KEY>` environment variable (for example,
`NOMAD_META_SERVICE=countdash-api`). They have no effect on scheduling.

---

### `config` block (Docker driver)

```hcl
config {
  image = "hashicorpdev/counter-api:${var.countdash-api-version}-${attr.cpu.arch}"
  ports = ["countdash-api"]
  mount {
    type   = "bind"
    source = "local/application.properties"
    target = "/application.properties"
  }
}
```

The `config` block is driver-specific. For the Docker driver:

| Field | Description |
|-------|-------------|
| `image` | Docker image to pull and run |
| `ports` | Names of ports (from the `network` block) to expose in the container |
| `mount` | Bind-mounts a file or directory from the host (or Nomad's task working directory) into the container. `source = "local/..."` refers to the Nomad task's `local/` scratch directory, which is populated by `template` blocks |

The web task additionally sets `auth_soft_fail = true`, so Nomad does not
fail the task if Docker registry authentication fails — the image is public
but the cluster may not have registry credentials configured.

**Multi-architecture image selection**: `hashicorpdev/counter-api:v3` and
`hashicorpdev/counter-dashboard:v3` are amd64-only images, not multi-arch
manifests — they don't run natively on arm64 hosts (e.g. Apple Silicon
Multipass VMs). HashiCorp separately publishes `v3-amd64` / `v3-arm64` tags
for both. `${attr.cpu.arch}` is a Nomad runtime node attribute that gets
interpolated into `image` after the scheduler places the allocation on a
specific node, resolving to `amd64` or `arm64` — combined with the
`countdash-api-version`/`countdash-web-version` variables (interpolated
separately, at job-submission time), this makes the job automatically pull
the correct architecture's image on whichever node it lands on, without
needing per-architecture task groups. This is not explicitly documented in
Nomad's own docs for the `image` field specifically — confirmed by testing
directly against a running cluster.

---

### `template` block

The `template` block renders a file into the task's working directory using
Go template syntax. Both tasks use it, for different purposes.

**Config file injection (API task)** — same as the Consul-based variant:

```hcl
template {
  data = "server.port=${var.countdash-api-port}"
  destination = "local/application.properties"
}
```

**Dynamic service address resolution (web task)** — this is the key
difference from the Consul-based variant:

```hcl
template {
  data = <<EOH
BIND_ADDRESS = ":${var.countdash-api-port}"
{{ range nomadService "countdash-api" }}
COUNTING_SERVICE_URL = "http://{{ .Address }}:{{ .Port }}"
{{ end }}
EOH
  destination = "local/env.txt"
  env         = true
}
```

`nomadService "countdash-api"` queries Nomad's own service catalog at
render time and returns all healthy instances of the `countdash-api`
service. The template iterates over the results and writes the IP and port
of the first instance into `COUNTING_SERVICE_URL`. Setting `env = true`
causes Nomad to export every `KEY = "value"` line in the rendered file as an
environment variable in the task, so the web container receives
`COUNTING_SERVICE_URL` at startup. Nomad re-renders the template and
restarts the task whenever the service catalog entry changes — this job has
no `env` block for the URL, since it's resolved dynamically here instead.

---

### `resources` block

```hcl
resources {
  memory = 500
}
```

`resources` reserves compute capacity on the client node for the task.
Nomad uses these values for scheduling decisions and to enforce limits.

| Field | Unit | Description |
|-------|------|-------------|
| `memory` | MB | Memory reservation and soft limit |
| `cpu` | MHz | CPU reservation (not set here; Nomad uses the default of 100 MHz) |

Only the API task specifies a `memory` reservation (500 MB) because the JVM
baseline footprint is significant. The web task uses the default.

---

## Comparison with the Consul variant

See [`../consul-sd/README.md`](../consul-sd/README.md) for the full
reference on the Consul-based variant. Summary of the differences:

| | This job (Nomad-native) | [`../consul-sd/`](../consul-sd/) (Consul) |
|-|--------------------------|------------------------|
| Service registration | Nomad catalog | Consul catalog |
| Web → API address resolution | `nomadService` template renders address at startup; task restarts on change | `.global` DNS name resolved at connection time via dnsmasq |
| `dns.servers` required | No | Yes (`172.17.0.1`) |
| Consul dependency | None | Required |
| Address update behaviour | Task restarts when catalog changes | Transparent (DNS TTL) |
