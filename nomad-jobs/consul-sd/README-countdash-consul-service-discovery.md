# Countdash — Consul Service Discovery

This directory contains [`countdash-consul-service-discovery.nomad.hcl`](countdash-consul-service-discovery.nomad.hcl),
one of three variants of the **Countdash** sample application — a two-tier
web app consisting of a Java Spring Boot counter API and a Go web dashboard.
This variant uses **Consul** for service discovery (DNS lookup via
dnsmasq). The other two variants live in sibling directories and demonstrate
different service-discovery mechanisms against the same app:

| File | Service discovery provider |
|------|----------------------------|
| `countdash-consul-service-discovery.nomad.hcl` (this directory) | Consul (DNS lookup via dnsmasq) |
| [`../nomad-sd/countdash-nomad-service-discovery.nomad.hcl`](../nomad-sd/countdash-nomad-service-discovery.nomad.hcl) | Nomad (built-in service catalog + template) — see [`../nomad-sd/README.md`](../nomad-sd/README.md) |
| [`../consul-mesh/countdash-consul-service-mesh.nomad.hcl`](../consul-mesh/countdash-consul-service-mesh.nomad.hcl) | Consul service mesh (Envoy Connect sidecars, bridge networking) — see [`../consul-mesh/README.md`](../consul-mesh/README.md) |

The mesh variant is deployed and verified through the Consul API Gateway, not
directly on a public port — see [`nomad-jobs/consul-mesh/README.md`](../consul-mesh/README.md)
for the full deploy order (service-defaults, intentions, gateway, http-route).

## Prerequisites

Consul cluster deployed and dnsmasq configured on all Nomad clients
(`deploy_consul_nomad_sd.yaml`). The [`../nomad-sd/`](../nomad-sd/) variant
needs only a Nomad cluster — no Consul required.


## AWS security group requirements

The Terraform security group defined in [`terraform/aws/network.tf`](../terraform/aws/network.tf)
includes the following ingress rules for the Countdash app:

| Port | Protocol | Direction | Purpose | Who needs access |
|------|----------|-----------|---------|------------------|
| `9002` | TCP | Ingress | Countdash web UI | Anyone accessing the dashboard from a browser |
| `9001` | TCP | — | Countdash API | Not open externally. The API is only reachable within the cluster via the `self = true` security group rule. |

### How traffic flows

```
Browser (your machine)
    │
    │  port 9002 (TCP, public internet)
    ▼
EC2 instance running countdash-web task  ──► address = attr.unique.network.ip-address
                                              (or attr.unique.platform.aws.public-hostname
                                               on AWS - see below, detected automatically)
    │
    │  port 9001 (TCP, VPC-internal)
    │  resolved via Consul DNS (.global) or Nomad template
    ▼
EC2 instance running countdash-api task  ──► address = attr.unique.network.ip-address
```

Both tasks register `attr.unique.network.ip-address` by default — the
platform-agnostic node attribute Nomad fingerprints on every host (AWS,
Multipass, bare metal). This replaced the AWS-only
`attr.unique.platform.aws.local-ipv4` / `attr.unique.platform.aws.public-hostname`
attributes so these jobs also run on Multipass, which has no public/private
network split.

**AWS caveat**: `attr.unique.network.ip-address` resolves to the EC2
instance's **private** IPv4. This doesn't affect actual reachability of the
browser-facing port (port 9002 is still opened directly via the security
group below, and a browser hits the instance's public IP/hostname directly —
that traffic never goes through Consul/Nomad service discovery). It does mean
`countdash-web`'s entry in the Consul/Nomad service catalog no longer shows
an externally-usable address on AWS by default. Two ways to get it:

**Option A — read it from Terraform**, no job spec changes needed. Find
which node `countdash-web` landed on (`nomad job status
countdash-consul-sd`, check the alloc's node name), then:

```bash
cd terraform/aws
terraform output client_public_ips_by_node   # or server_public_ips_by_node
# {"nomad-client-1" = "1.2.3.4", "nomad-client-2" = "5.6.7.8", ...}
```

keyed directly by the Nomad node name shown in `nomad job status` — no
index cross-referencing against the separate public/private IP lists
required.

**Option B — the job spec registers the public hostname itself, automatically**.
`countdash-consul-service-discovery.nomad.hcl`, `countdash-nomad-service-discovery.nomad.hcl`,
and `hashicups-multipass.nomad.hcl` (its `nginx` group) all expose a
`deployment_platform` variable (default `"generic"` →
`attr.unique.network.ip-address`; `"aws"` → `attr.unique.platform.aws.public-hostname`).
You do not need to pass `-var` by hand — source
[`ansible/set-cluster-env.sh`](../../ansible/set-cluster-env.sh) before
running any of these jobs (you already do this for `CONSUL_HTTP_ADDR` /
`NOMAD_TOKEN` / etc.), and it detects the platform from `ansible/inventory.ini`
and exports `NOMAD_VAR_deployment_platform` for you — Nomad's CLI reads
`NOMAD_VAR_<name>` exactly like `-var <name>=value`:

```bash
cd ansible && source ./set-cluster-env.sh   # also exports NOMAD_VAR_deployment_platform
cd ../nomad-jobs/consul-sd
nomad job run countdash-consul-service-discovery.nomad.hcl   # no -var needed
```

**Why this needs an env var instead of being fully automatic (e.g. driven by
Nomad node metadata Ansible could set with zero shell setup)**: tried that
first — confirmed by live testing, not assumed. Nomad's `service.address`
field only resolves this ternary correctly when its *condition* is a `var.*`
value, known at job-submission time before any node is chosen. A node-level
`attr.*`/`meta.*` condition (which Ansible could set automatically, no
sourcing required) silently resolves to the wrong (private-IP) branch with
**no error**, even when genuinely true on that node — confirmed with a
`constraint` block on the identical attribute as a control test, which
correctly matched, proving the value itself was fine; only its use as this
ternary's condition failed. Full write-up in
[`_context/wiki/deployment-platform-auto-detection.md`](../../_context/wiki/deployment-platform-auto-detection.md).

**Sharp edge that still applies** (now much less likely to hit, since the
env var is set automatically rather than typed by hand each time): each
*branch* of the ternary (as opposed to its condition) is still resolved
per-node, at runtime. If `NOMAD_VAR_deployment_platform` somehow doesn't
match the platform you're actually deploying to (e.g. `set-cluster-env.sh`
wasn't sourced, or `inventory.ini` is stale), Nomad does not error — it
silently registers the literal unresolved text
`${attr.unique.platform.aws.public-hostname}` as the service address, which
then fails the health check trying to parse that literal text as a URL
(`invalid URL escape "%7B"` in the check output). If you see that exact
error, `NOMAD_VAR_deployment_platform` doesn't match reality — re-source
`set-cluster-env.sh`, don't edit the job spec.

Option A remains useful as a fallback/cross-check independent of the job
spec, or if you need the public IP/hostname without deploying anything.

### Security note

Port `9001` has no external ingress rule. The API is only reachable from other instances inside the same security group (via the `self = true` rule), which covers all cross-node traffic within the cluster. Port `9002` must remain publicly accessible for the web UI to be usable.

To add or modify ingress rules without editing Terraform, use the Ansible playbook:

```bash
cd ansible
ansible-playbook update-security-group.yaml \
  -e custom_port=9002 \
  -e custom_port_description="Countdash web UI"
```

Refer to [`ansible/README-SECURITY-GROUP.md`](../ansible/README-SECURITY-GROUP.md) for full playbook usage.

## Running the job

```bash
nomad job run countdash-consul-service-discovery.nomad.hcl
```

To run the Nomad-native variant instead, see
[`../nomad-sd/README.md`](../nomad-sd/README.md).

Override a default port at run time:

```bash
nomad job run -var="countdash-api-port=9010" countdash-consul-service-discovery.nomad.hcl
```

---

## Job specification reference

The sections below walk through every stanza used in this file and explain
what each one does. The Nomad-native variant
([`../nomad-sd/`](../nomad-sd/)) shares most of this structure — differences
are called out inline and summarized in
["Comparison with the Nomad-native variant"](#comparison-with-the-nomad-native-variant)
at the end.

### `variable` blocks

```hcl
variable "countdash-api-port" {
  description = "Countdash API Port"
  default = 9001
}
```

Top-level variables set defaults that can be overridden at `nomad job run`
time with the `-var` flag. They are referenced elsewhere in the file with
`var.<name>`. This job exposes:

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
job "countdash-consul-sd" { ... }
```

The top-level `job` block names the job and contains all groups, tasks, and
configuration for the deployment. The job name is used by the Nomad scheduler
and appears in the UI and CLI output. `countdash-consul-service-discovery.nomad.hcl`
and `countdash-nomad-service-discovery.nomad.hcl` use distinct job names
(`countdash-consul-sd` / `countdash-nomad-sd`) specifically so both can be
deployed to the same cluster at once without one overwriting the other — they
used to share the job name `countdash` until this was fixed, which meant
running one silently replaced the other via an in-place job update.

---

### `group` block

```hcl
group "countdash-api" {
  count = 1
  ...
}
```

A group is a set of tasks that are co-scheduled on the same Nomad client node.
`count` controls how many instances of the group to run. This job has two
groups:

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
  dns {
    servers = ["172.17.0.1"]
  }
}
```

The `network` block is defined at the group level and controls the network
configuration for all tasks in the group.

**`port` stanza**

`static` binds the container to a fixed port on the host rather than letting
Nomad assign a dynamic port. Static ports are used here because the
applications read their own port from environment variables or config files, so
they must be predictable.

**`dns` stanza**

`dns.servers` passes a list of DNS resolver addresses to Docker via the
`--dns` flag. `172.17.0.1` is the Docker bridge gateway — the address of
the host as seen from inside a Docker container. Pointing containers to
this address routes their DNS queries to dnsmasq, which forwards `.global`
lookups to the local Consul agent (port 8600) and everything else to the
AWS VPC resolver. This stanza is what makes `.global` DNS names (used in the
`env` block below) resolvable from inside the container — the Nomad-native
variant omits it entirely, since it doesn't perform `.global` DNS lookups.

---

### `service` block

```hcl
service {
  name     = "countdash-api"
  provider = "consul"
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
| `provider` | `"consul"` — registers with Consul (the Nomad-native variant uses `"nomad"` instead; see [comparison table](#comparison-with-the-nomad-native-variant)) |
| `port` | References the named port from the `network` block |
| `address` | Overrides the registered IP/hostname. `attr.unique.network.ip-address` is the platform-agnostic node attribute Nomad fingerprints on every host — resolves to the private IPv4 on AWS, the single bridged-network IP on Multipass. Both `countdash-api` and `countdash-web` use the same attribute (see the AWS caveat under "How traffic flows" above for what this means for the web tier specifically on AWS) |

---

### `check` block

```hcl
check {
  name     = "Countdash API ready"
  type     = "http"
  path     = "/actuator/health"
  interval = "5s"
  timeout  = "5s"
}
```

Health checks run on the same node as the task. Consul polls the check
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
restart. `limit = 0` disables automatic restarts on health failure — the task
stays running even if the check fails. This is set only on the API task, where
a cold JVM startup can take longer than the check timeout, preventing premature
restart loops during initialization.

---

### `task` block

```hcl
task "countdash-api" {
  driver = "docker"
  ...
}
```

A `task` is the smallest schedulable unit in Nomad. The `driver` field selects
the task driver responsible for running the workload — `"docker"` here.

---

### `meta` block

```hcl
meta {
  service = "countdash-api"
}
```

`meta` attaches arbitrary key-value metadata to the task. These values appear
in `nomad alloc inspect` output and can be read from within the task via the
`NOMAD_META_<KEY>` environment variable (for example,
`NOMAD_META_SERVICE=countdash-api`). They have no effect on scheduling.

---

### `config` block (Docker driver)

```hcl
config {
  image          = "hashicorpdev/counter-api:${var.countdash-api-version}-${attr.cpu.arch}"
  ports          = ["countdash-api"]
  auth_soft_fail = true
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
| `auth_soft_fail` | When `true`, Nomad does not fail the task if Docker registry authentication fails. Used on the web task because the image is public but the cluster may not have registry credentials configured |
| `mount` | Bind-mounts a file or directory from the host (or Nomad's task working directory) into the container. `source = "local/..."` refers to the Nomad task's `local/` scratch directory, which is populated by `template` blocks |

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
Go template syntax, used here only for config file injection (API task):

```hcl
template {
  data        = "server.port=${var.countdash-api-port}"
  destination = "local/application.properties"
}
```

Renders a Spring Boot properties file at `local/application.properties` and
bind-mounts it into the container (see `mount` above). This injects the port
at job submission time so the Java process listens on the correct port without
rebuilding the image.

Unlike the Nomad-native variant, this job does *not* use `template` for
service address resolution — see the `env` block below and the
[comparison table](#comparison-with-the-nomad-native-variant) for why.

---

### `env` block

```hcl
env {
  COUNTING_SERVICE_URL = "http://countdash-api.service.dc1.global:${var.countdash-api-port}"
  PORT = "${var.countdash-web-port}"
}
```

*(web task only)*

`env` sets static environment variables in the container.
`COUNTING_SERVICE_URL` is a hardcoded Consul DNS name
(`countdash-api.service.dc1.global`) that resolves at runtime via dnsmasq —
simpler than the Nomad-native variant's `nomadService` template approach, but
requires Consul and dnsmasq to be deployed and functioning on the client
node.

---

### `resources` block

```hcl
resources {
  memory = 500
}
```

`resources` reserves compute capacity on the client node for the task. Nomad
uses these values for scheduling decisions and to enforce limits.

| Field | Unit | Description |
|-------|------|-------------|
| `memory` | MB | Memory reservation and soft limit |
| `cpu` | MHz | CPU reservation (not set here; Nomad uses the default of 100 MHz) |

Only the API task specifies a `memory` reservation (500 MB) because the JVM
baseline footprint is significant. The web task uses the default.

---

## Comparison with the Nomad-native variant

See [`../nomad-sd/README.md`](../nomad-sd/README.md) for the full reference
on the Nomad-native variant. Summary of the differences:

| | This job (Consul) | [`../nomad-sd/`](../nomad-sd/) (Nomad-native) |
|-|--------------------------|------------------------|
| Service registration | Consul catalog | Nomad catalog |
| Web → API address resolution | `.global` DNS name resolved at connection time via dnsmasq | `nomadService` template renders address at startup; task restarts on change |
| `dns.servers` required | Yes (`172.17.0.1`) | No |
| Consul dependency | Required | None |
| Address update behaviour | Transparent (DNS TTL) | Task restarts when catalog changes |
