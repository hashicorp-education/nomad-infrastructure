# Nomad Jobs

This directory contains two versions of the **Countdash** sample application — a
two-tier web app consisting of a Java Spring Boot counter API and a Go web
dashboard. The two versions demonstrate the difference between Consul-based and
Nomad-native service discovery.

| File | Service discovery provider |
|------|----------------------------|
| [`countdash-consul-service-discovery.nomad.hcl`](countdash-consul-service-discovery.nomad.hcl) | Consul (DNS lookup via dnsmasq) |
| [`countdash-nomad-service-discovery.nomad.hcl`](countdash-nomad-service-discovery.nomad.hcl) | Nomad (built-in service catalog + template) |

## Prerequisites

| Job | Requirement |
|-----|-------------|
| `countdash-consul-service-discovery` | Consul cluster deployed and dnsmasq configured on all Nomad clients (`deploy_consul_nomad_sd.yaml`) |
| `countdash-nomad-service-discovery` | Nomad cluster only — no Consul required |


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
EC2 instance running countdash-web task  ──► address = attr.unique.platform.aws.public-hostname
    │
    │  port 9001 (TCP, VPC-internal)
    │  resolved via Consul DNS (.global) or Nomad template
    ▼
EC2 instance running countdash-api task  ──► address = attr.unique.platform.aws.local-ipv4
```

Both tasks are registered with their respective addresses:

- `countdash-web` registers the EC2 **public hostname** so the browser can reach the dashboard directly on port `9002`.
- `countdash-api` registers the EC2 **private IPv4** so inter-node traffic between the web container and the API stays within the VPC (port `9001`).

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

## Running the jobs

```bash
# Consul service discovery variant
nomad job run countdash-consul-service-discovery.nomad.hcl

# Nomad service discovery variant
nomad job run countdash-nomad-service-discovery.nomad.hcl
```

Override a default port at run time:

```bash
nomad job run -var="countdash-api-port=9010" countdash-consul-service-discovery.nomad.hcl
```

---

## Job specification reference

The sections below walk through every stanza used in these files and explain
what each one does.

### `variable` blocks

```hcl
variable "countdash-api-port" {
  description = "Countdash API Port"
  default = 9001
}
```

Top-level variables set defaults that can be overridden at `nomad job run`
time with the `-var` flag. They are referenced elsewhere in the file with
`var.<name>`. Both jobs expose two variables:

| Variable | Default | Purpose |
|----------|---------|---------|
| `countdash-api-port` | `9001` | Static port bound by the API container |
| `countdash-web-port` | `9002` | Static port bound by the web container |

---

### `job` block

```hcl
job "countdash" { ... }
```

The top-level `job` block names the job (`countdash`) and contains all groups,
tasks, and configuration for the deployment. The job name is used by the Nomad
scheduler and appears in the UI and CLI output.

---

### `group` block

```hcl
group "countdash-api" {
  count = 1
  ...
}
```

A group is a set of tasks that are co-scheduled on the same Nomad client node.
`count` controls how many instances of the group to run. Both jobs have two
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

**`dns` stanza** *(Consul job only)*

`dns.servers` passes a list of DNS resolver addresses to Docker via the
`--dns` flag. `172.17.0.1` is the Docker bridge gateway — the address of
the host as seen from inside a Docker container. Pointing containers to
this address routes their DNS queries to dnsmasq, which forwards `.global`
lookups to the local Consul agent (port 8600) and everything else to the
AWS VPC resolver. This stanza is absent from the Nomad service discovery job
because that job does not perform `.global` DNS lookups.

---

### `service` block

```hcl
service {
  name     = "countdash-api"
  provider = "consul"          # or "nomad"
  port     = "countdash-api"
  address  = attr.unique.platform.aws.local-ipv4
  ...
}
```

The `service` block registers the task with a service catalog so other
services can discover it.

| Field | Description |
|-------|-------------|
| `name` | Name under which the service is registered in the catalog |
| `provider` | `"consul"` to register with Consul; `"nomad"` to register with Nomad's built-in catalog |
| `port` | References the named port from the `network` block |
| `address` | Overrides the registered IP/hostname. `attr.unique.platform.aws.local-ipv4` is a Nomad runtime attribute that resolves to the EC2 instance's private IPv4. The web service uses `attr.unique.platform.aws.public-hostname` so the dashboard is reachable from outside the VPC |

**Provider differences**

| Aspect | `provider = "consul"` | `provider = "nomad"` |
|--------|----------------------|----------------------|
| Catalog | Consul service catalog | Nomad built-in catalog |
| DNS lookup | `<name>.service.<dc>.global` via dnsmasq | Not available via DNS |
| Template function | `{{ service "name" }}` | `{{ nomadService "name" }}` |
| Requires Consul | Yes | No |

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

Health checks run on the same node as the task. Nomad (or Consul, when
`provider = "consul"`) polls the check endpoint on the given `interval` and
marks the service unhealthy if the check does not respond within `timeout`.

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
the task driver responsible for running the workload. Both jobs use `"docker"`.

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
  image          = "hashicorpdev/counter-api:v3"
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

---

### `template` block

The `template` block renders a file into the task's working directory using
Go template syntax. The two jobs use templates for different purposes.

**Config file injection (both jobs — API task)**

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

**Dynamic service address resolution (Nomad service discovery job — web task)**

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

`nomadService "countdash-api"` queries the Nomad service catalog at render
time and returns all healthy instances of the `countdash-api` service. The
template iterates over the results and writes the IP and port of the first
instance into `COUNTING_SERVICE_URL`. Setting `env = true` causes Nomad to
export every `KEY = "value"` line in the rendered file as an environment
variable in the task, so the web container receives `COUNTING_SERVICE_URL`
at startup. Nomad re-renders the template and restarts the task whenever the
service catalog entry changes.

---

### `env` block

```hcl
env {
  COUNTING_SERVICE_URL = "http://countdash-api.service.dc1.global:${var.countdash-api-port}"
  PORT = "${var.countdash-web-port}"
}
```

*(Consul service discovery job — web task only)*

`env` sets static environment variables in the container. In the Consul
variant, `COUNTING_SERVICE_URL` is a hardcoded Consul DNS name
(`countdash-api.service.dc1.global`) that resolves at runtime via dnsmasq.
This is simpler than the `nomadService` template but requires Consul and
dnsmasq to be deployed and functioning on the client node.

The Nomad service discovery job does not use an `env` block for the URL
because it resolves the address dynamically through the `template` block
described above.

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

## Key difference between the two jobs

| | Consul service discovery | Nomad service discovery |
|-|--------------------------|------------------------|
| Service registration | Consul catalog | Nomad catalog |
| Web → API address resolution | `.global` DNS name resolved at connection time via dnsmasq | `nomadService` template renders address at startup; task restarts on change |
| `dns.servers` required | Yes (`172.17.0.1`) | No |
| Consul dependency | Required | None |
| Address update behaviour | Transparent (DNS TTL) | Task restarts when catalog changes |
