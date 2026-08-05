# Run Nomad in dev mode on macOS

A guide to `-dev`, `-dev-consul`, and `-dev-connect` modes, with Docker Desktop setup, gotchas, and example jobs.

---

## Contents

1. [Prerequisites & installation](#1-prerequisites--installation)
2. [Docker Desktop configuration](#2-docker-desktop-configuration-required)
3. [Understanding the dev flags](#3-understanding-the-dev-flags)
4. [Running: `-dev` (basic)](#4-running--dev-basic)
5. [Running: `-dev-consul` (Consul workload identity)](#5-running--dev-consul-consul-workload-identity)
6. [Running: `-dev-connect` (Linux only)](#6-running--dev-connect--linux-only)
7. [Ports & URLs](#7-ports--urls)
8. [Example jobs](#8-example-jobs)
9. [Countdash: Nomad service discovery](#9-countdash-nomad-service-discovery)
10. [Countdash: Consul service discovery](#10-countdash-consul-service-discovery)
11. [Useful CLI commands](#11-useful-cli-commands)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites & installation

### Install Nomad

The recommended method on macOS is Homebrew:

```bash
brew tap hashicorp/tap
brew install hashicorp/tap/nomad

# Verify
nomad version
```

Or download a binary from <https://developer.hashicorp.com/nomad/downloads>, unzip it, and place it somewhere on your `$PATH` (for example, `/usr/local/bin/`).

### What you need

| Requirement | Notes |
|---|---|
| macOS (Apple Silicon or Intel) | All dev modes except `-dev-connect` work on macOS |
| Docker Desktop installed and running | Required for Docker driver jobs. See [Section 2](#2-docker-desktop-configuration-required) for configuration. |
| Consul binary (optional) | Only needed if running Consul alongside Nomad. Not required for `-dev` alone. |

---

## 2. Docker Desktop configuration (Required)

Two Docker Desktop settings must be changed or Nomad fails to detect the Docker driver and jobs fail with mount permission errors.

### Step 1: Enable the default Docker socket

Nomad communicates with Docker over `/var/run/docker.sock`. Docker Desktop disables this socket by default on recent versions.

1. Open Docker Desktop, then go to **Settings > Advanced**.
2. Select **Allow the default Docker socket to be used (requires password)**.
3. Click **Apply & Restart**.

### Step 2: Switch virtualization framework (if you see mount permission errors)

Docker Desktop's default **VirtioFS** file sharing causes permission errors when Nomad writes allocation data to the host. Switch to gRPC FUSE:

1. Go to Docker Desktop **Settings > General**.
2. Under **Virtual file sharing implementation**, switch from **VirtioFS** to **gRPC FUSE**.
3. Click **Apply & Restart**.

> **Note:** Apply both settings before starting Nomad. If Nomad starts before Docker's socket is exposed, the Docker driver fingerprint fails and no Docker jobs run. Restart Nomad after fixing Docker Desktop.

---

## 3. Understanding the dev flags

All dev flags build on top of each other. The following table reflects what each flag sets, sourced directly from [`command/agent/config.go:DevConfig()`](https://github.com/hashicorp/nomad/blob/main/command/agent/config.go).

| Flag | macOS | What it sets |
|---|---|---|
| `-dev` | ✅ works | Dual-role agent (server + client) bound to `127.0.0.1` / `lo0`; log level DEBUG; `driver.raw_exec.enable = true`; `driver.docker.volumes = true`; Nomad service discovery on; Prometheus metrics on; GC thresholds relaxed (99% disk/inode); no `data_dir` needed — state is in-memory |
| `-dev-consul` | ✅ works | Everything in `-dev`, plus Consul `service_identity` and `task_identity` workload identities (audience: `consul.io`, TTL: 1h). Requires a running Consul agent to be useful. |
| `-dev-connect` | ❌ Linux only | Binds to public interface for Consul service mesh; requires Linux, root, and `consul` binary on `$PATH`; uses network namespaces. Not available on macOS. |
| `-dev-vault` | ✅ works | Everything in `-dev`, plus Vault integration pointing to `http://localhost:8200` with default workload identity (audience: `vault.io`, TTL: 1h). Requires a running Vault dev server. |

Flags are combinable: `nomad agent -dev-consul -dev-vault` activates all three sets of defaults simultaneously.

> **`-dev-connect` is Linux-only (enforced in source code)**
> [`command/agent/config.go`](https://github.com/hashicorp/nomad/blob/main/command/agent/config.go) explicitly checks `runtime.GOOS != "linux"` and returns an error on macOS. It requires Linux network namespaces for service mesh traffic interception. There is no workaround on macOS. Use a Linux VM or Docker container for service mesh testing.

> **State is not persisted in dev mode**
> Dev mode has no `data_dir`. All state — jobs, allocations, node registration — lives in memory and is lost when Nomad exits. This is intentional for quick iteration.

---

## 4. Running: `-dev` (basic)

This is the fastest way to get a single-node Nomad cluster running on your Mac.

```bash
# Start Nomad in dev mode (leave this terminal running)
nomad agent -dev
```

You should see output like:

```
==> Nomad agent configuration:
       Bind Address: 127.0.0.1
     Data Directory: <in-memory>
            Dev Mode: true
==> Nomad agent started! Log data will stream in below:
```

Nomad runs as a combined server + client. The UI and API are immediately available.

### Verify it's working

```bash
# In a second terminal:
nomad node status
nomad server members

# Open the Web UI
open http://localhost:4646
```

### Persist data across restarts (optional)

Add `-data-dir` to keep jobs and allocation state across agent restarts. This exits pure in-memory mode but keeps all other dev defaults:

```bash
mkdir -p /tmp/nomad-dev
nomad agent -dev -data-dir=/tmp/nomad-dev
```

---

## 5. Running: `-dev-consul` (Consul workload identity)

Use this when you want Nomad to integrate with a local Consul agent for service registration, health checks, and workload identity tokens.

### Step 1: Start a Consul dev agent

```bash
# Install Consul if needed
brew install hashicorp/tap/consul

# Run Consul in dev mode (separate terminal)
consul agent -dev -client=0.0.0.0
```

### Step 2: Start Nomad with `-dev-consul`

```bash
nomad agent -dev-consul
```

This configures two workload identities automatically (from the source code):

- **Service identity**: audience `consul.io`, TTL 1 hour. Used by Nomad services registering in Consul.
- **Task identity**: audience `consul.io`, TTL 1 hour. Used by tasks needing Consul tokens.

### What `-dev-consul` does not do

It does not configure service mesh or Connect sidecar proxies. That requires `-dev-connect` on Linux. On macOS you can register services and use health checks, but not Envoy-based traffic interception.

### Verify Consul integration

```bash
# Check Consul sees Nomad
curl http://localhost:8500/v1/catalog/services | python3 -m json.tool

# Open Consul UI
open http://localhost:8500
```

---

## 6. Running: `-dev-connect` (Linux only)

`-dev-connect` is not available on macOS. Running it exits immediately with:

```
-dev-connect is only supported on linux.
```

If you need to test Consul service mesh locally, the following options are available:

1. **Linux VM** using UTM, VMware Fusion, or Parallels. Run a full Linux VM and install Nomad and Consul there.
2. **Vagrant**: run `vagrant init hashicorp/bionic64 && vagrant up`, then install Nomad inside.
3. **GitHub Codespaces or a remote Linux dev box**: run `nomad agent -dev-connect` as root there.

To run it on Linux:

```bash
# On Linux, as root, with consul binary on $PATH:
sudo nomad agent -dev-connect

# Combined with Consul workload identity:
sudo nomad agent -dev-connect -dev-consul
```

`-dev-connect` binds to `0.0.0.0` and uses the first non-loopback network interface instead of `lo`, enabling Envoy proxy sidecar injection through network namespaces.

---

## 7. Ports & URLs

| Service | Port | URL |
|---|---|---|
| Nomad HTTP API + Web UI | 4646 | <http://localhost:4646> |
| Nomad RPC | 4647 | — |
| Nomad Serf (gossip) | 4648 | — |
| Consul HTTP API + UI | 8500 | <http://localhost:8500> (if running) |
| Consul DNS | 8600 | — |
| Dynamic alloc ports | 20000–32000 | Assigned per allocation |
| Client alloc ports | 14000–14512 | Used internally by the client |
| Prometheus metrics | 4646 | <http://localhost:4646/v1/metrics?format=prometheus> |

---

## 8. Example jobs

### Hello World: raw_exec driver

The `raw_exec` driver runs a binary directly on the host. It is enabled automatically in dev mode.

```hcl
# hello.nomad.hcl
job "hello" {
  type = "batch"

  group "grp" {
    task "echo" {
      driver = "raw_exec"

      config {
        command = "/bin/echo"
        args    = ["Hello from Nomad!"]
      }
    }
  }
}
```

```bash
nomad job run hello.nomad.hcl
nomad job status hello

# View logs:
nomad alloc logs <alloc-id>
```

### Docker job

Docker volume mounts are enabled in dev mode (`driver.docker.volumes = true`).

```hcl
# nginx.nomad.hcl
job "nginx" {
  group "web" {
    network {
      port "http" {
        static = 8080
      }
    }

    task "nginx" {
      driver = "docker"

      config {
        image = "nginx:alpine"
        ports = ["http"]
      }

      resources {
        cpu    = 100
        memory = 64
      }
    }
  }
}
```

```bash
nomad job run nginx.nomad.hcl
# Once running:
curl http://localhost:8080
```

### Docker job using a local image

> **Important:** Tag your local images with an explicit version. Never use `:latest` for local-only images.
> Images tagged `:latest` trigger a pull attempt. Nomad tries to pull from the registry and fails if the image is local-only.

```bash
# Build your image with an explicit tag
docker build -t my-app:v1.0.0 .
```

```hcl
# In your job spec:
config {
  image              = "my-app:v1.0.0"
  image_pull_timeout = "5m"
}
```

---

## 9. Countdash: Nomad service discovery

The Countdash application is a two-tier demo consisting of a Java API (`countdash-api`) that increments a counter and a Go dashboard (`countdash-web`) that renders the current count in a browser. This variant registers both services with **Nomad's built-in service discovery** (`provider = "nomad"`). No Consul installation is needed.

### How service discovery works in this job

The `countdash-web` task uses a `nomadService` template function to look up the API's address at runtime:

```hcl
template {
  data = <<EOH
{{ range nomadService "countdash-api" }}
COUNTING_SERVICE_URL = "http://{{ .Address }}:{{ .Port }}"
{{ end }}
EOH
  destination = "local/env.txt"
  env         = true
}
```

When the template renders, Nomad substitutes the live address and port of the `countdash-api` service. The dashboard reads `COUNTING_SERVICE_URL` from its environment and connects directly. No DNS or external catalog is required.

### Image architecture

Both images are published as separate `amd64` and `arm64` tags (for example, `hashicorpdev/counter-api:v3-arm64`). The job spec appends `${attr.cpu.arch}` to the version prefix at task-start time, so the correct image is pulled automatically on both Intel and Apple Silicon Macs.

### Prerequisites

- Nomad running with `nomad agent -dev` (no Consul needed)
- Docker Desktop configured as described in [Section 2](#2-docker-desktop-configuration-required)

### Deploy

```bash
nomad job run countdash-nomad-service-discovery.nomad.hcl
```

Verify both groups started:

```bash
nomad job status countdash-nomad-sd
```

Open the dashboard. It listens on port `9002` by default:

```bash
open http://localhost:9002
```

The counter increments every second. The number is served by the API on port `9001`.

### Verify service registrations

```bash
# List services registered with Nomad's catalog
nomad service list

# Show details for a specific service
nomad service info countdash-api
nomad service info countdash-web
```

### Override defaults

All ports and image versions are exposed as variables:

```bash
# Change ports
nomad job run \
  -var="countdash-api-port=19001" \
  -var="countdash-web-port=19002" \
  countdash-nomad-service-discovery.nomad.hcl

# Pin to a specific image version
nomad job run \
  -var="countdash-api-version=v3" \
  -var="countdash-web-version=v3" \
  countdash-nomad-service-discovery.nomad.hcl
```

Nomad also reads `NOMAD_VAR_<name>` environment variables the same as `-var <name>=value` — but the match against the variable's declared name is a literal string comparison (`jobspec2/types.variables.go`), and this job's variables are hyphenated (`countdash-api-port`, `countdash-web-port`). Shell environment variable names can't contain hyphens, so there is no `NOMAD_VAR_...` spelling that matches them: `export NOMAD_VAR_countdash_api_port=19001` sets a variable Nomad has never heard of, and it is silently ignored — no error, no override. Use `-var` for these two jobs; `NOMAD_VAR_` only works for variables whose names are already valid shell identifiers (underscores, no hyphens).

### Stop and clean up

```bash
nomad job stop -purge countdash-nomad-sd
```

---

## 10. Countdash: Consul service discovery

This variant of the same two-tier application registers both services with **Consul** (`provider = "consul"`). The dashboard resolves the API address using a Consul DNS name rather than a Nomad template lookup.

### How service discovery works in this job

Instead of a `nomadService` template, `countdash-web` receives the API URL as a static environment variable that uses the Consul DNS name:

```hcl
env {
  COUNTING_SERVICE_URL = "http://countdash-api.service.dc1.global:${var.countdash-api-port}"
  PORT                 = "${var.countdash-web-port}"
}
```

`countdash-api.service.dc1.global` is the Consul DNS address for the `countdash-api` service in datacenter `dc1`. Consul resolves this to the registered IP of the healthy API instance. Each group also sets a custom DNS resolver for Docker containers:

```hcl
network {
  dns {
    servers = ["172.17.0.1"]
  }
}
```

`172.17.0.1` is the Docker bridge gateway address. When Consul is running with `-client=0.0.0.0`, it forwards DNS queries on port `8600` to Consul, which lets containers resolve `.consul` DNS names.

The Consul variant also adds `shutdown_delay = "10s"` to both groups, giving Consul time to propagate deregistration before the containers stop receiving traffic.

### Prerequisites

| Step | Command |
|---|---|
| 1. Start Consul | `consul agent -dev -client=0.0.0.0 -domain=global` |
| 2. Start Nomad | `nomad agent -dev-consul` |

> **Order matters:** Start Consul first, then Nomad. The `-dev-consul` flag configures Nomad's workload identity integration, which requires Consul to already be running.
>
> **`-domain=global` is required for this job.** The job spec below resolves the API at `countdash-api.service.dc1.global` — the `.global` suffix matches this repo's Consul DNS domain convention (see `ansible/group_vars/all.yaml`), chosen to avoid clashing with the ICANN-registered `.consul` TLD. Consul's own dev-mode default domain is `consul.`, not `global` (`agent/config/default.go`). If you start Consul with plain `consul agent -dev -client=0.0.0.0`, the job's DNS lookups will fail with NXDOMAIN because the agent only answers on `*.consul`, not `*.global`.

### Deploy

```bash
nomad job run countdash-consul-service-discovery.nomad.hcl
```

Verify both groups started:

```bash
nomad job status countdash-consul-sd
```

Confirm services are registered in Consul:

```bash
consul catalog services
# Expected: consul, countdash-api, countdash-web, nomad, nomad-client

curl http://localhost:8500/v1/health/service/countdash-api?passing | python3 -m json.tool
```

Open the dashboard:

```bash
open http://localhost:9002
```

### Verify DNS resolution

If the dashboard shows a connection error instead of a count, verify that Consul DNS is resolving correctly from inside Docker:

```bash
# Find the running countdash-web allocation ID
nomad job allocs countdash-consul-sd

# Exec into the container and test DNS
nomad alloc exec <alloc-id> -task countdash-web /bin/sh -c \
  "nslookup countdash-api.service.dc1.global 172.17.0.1"
```

If DNS resolution fails, confirm Consul is listening on `0.0.0.0` (not `localhost`):

```bash
lsof -i :8600 | grep LISTEN
# Should show consul bound to *:8600, not localhost:8600
```

### Compare: Nomad SD vs Consul SD

| Aspect | Nomad SD (`provider = "nomad"`) | Consul SD (`provider = "consul"`) |
|---|---|---|
| External dependency | None | Consul agent required |
| Service URL resolution | `nomadService` template function renders at task start | Consul DNS name (`*.service.dc1.global`) resolved at runtime |
| DNS setup | Not required | Docker bridge DNS (`172.17.0.1`) must forward to Consul |
| Graceful drain | Not configured | `shutdown_delay = "10s"` lets Consul propagate deregistration |
| macOS support | Full | Full (Connect/sidecar proxies require Linux) |

### Override defaults

The same variables are available as in the Nomad SD job:

```bash
nomad job run \
  -var="countdash-api-port=19001" \
  -var="countdash-web-port=19002" \
  countdash-consul-service-discovery.nomad.hcl
```

### Stop and clean up

```bash
nomad job stop -purge countdash-consul-sd

# Confirm Consul deregistered the services
consul catalog services
```

---

## 11. Useful CLI commands

```bash
# Watch all running jobs
nomad job list

# Submit a job
nomad job run <file.nomad.hcl>

# Check job status
nomad job status <job-name>

# List allocations for a job
nomad job allocs <job-name>

# Stream logs from an allocation
nomad alloc logs -f <alloc-id>

# Stop a job (and clean up allocations)
nomad job stop <job-name>

# Purge a stopped job completely
nomad job stop -purge <job-name>

# Exec into a running task (like docker exec)
nomad alloc exec <alloc-id> /bin/sh

# Inspect node details (driver fingerprint, resources)
nomad node status -verbose <node-id>

# Validate a job file without submitting
nomad job validate <file.nomad.hcl>

# Watch Prometheus metrics (enabled automatically in dev mode)
curl -s http://localhost:4646/v1/metrics?format=prometheus | grep nomad_client
```

---

## 12. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Docker driver not detected / shown as "unhealthy" | Docker Desktop socket not exposed | Go to **Settings > Advanced**, then enable **Allow the default Docker socket to be used**. Restart Docker Desktop, then restart Nomad. |
| Job fails with mount permission error | VirtioFS virtualization conflicts with Nomad's alloc dir writes | Go to **Settings > General**, then switch from **VirtioFS** to **gRPC FUSE**. Restart Docker Desktop and Nomad. |
| `-dev-connect is only supported on linux` | Running on macOS | Use a Linux VM or remote dev box. `-dev-connect` requires Linux network namespaces. |
| Docker image pull fails for local image | Image tagged `:latest` triggers remote pull | Use a specific tag (for example, `myimage:v1`) and set `image_pull_timeout` in the task configuration. |
| Nomad exits: "Must specify either server, client or dev mode" | Started with no role flags and no configuration file | Add `-dev`, or use `-server -bootstrap-expect=1 -data-dir=/tmp/nomad`. |
| Consul services not appearing in Nomad UI | Consul not running or not on default address | Start `consul agent -dev -client=0.0.0.0` before Nomad, then use `-dev-consul`. |
| Countdash dashboard can't reach the API (Consul SD variant) | Consul agent is using the default `consul.` DNS domain, but the job resolves `*.service.dc1.global` | Start Consul with `-domain=global` (see [Section 10](#10-countdash-consul-service-discovery)). |
| Address already in use on port `4646`/`4647`/`4648` | Another Nomad process is running | Run `pkill -f "nomad agent"` or `lsof -i :4646` to find and stop the process. |
| Alloc stuck in "pending" indefinitely | No eligible client or driver not detected | Run `nomad node status -verbose` to inspect fingerprinted drivers. Check Docker socket. |

### Quick health check script

```bash
#!/bin/bash
echo "=== Nomad status ==="
nomad server members 2>/dev/null || echo "Nomad not reachable on :4646"
nomad node status 2>/dev/null

echo ""
echo "=== Docker socket ==="
ls -la /var/run/docker.sock 2>/dev/null || echo "Docker socket not found"
docker info --format '{{.ServerVersion}}' 2>/dev/null || echo "Docker not running"

echo ""
echo "=== Port check ==="
lsof -i :4646 -i :4647 -i :4648 2>/dev/null | grep LISTEN
```
