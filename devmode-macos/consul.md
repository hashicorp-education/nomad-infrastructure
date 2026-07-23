# Run Consul in dev mode on macOS

A comprehensive guide to the `consul agent -dev` flag: what it sets, how to run it on macOS, useful flag combinations, and a practical primer on the HTTP API and service discovery.

---

## Contents

1. [Prerequisites and installation](#1-prerequisites-and-installation)
2. [Understanding `-dev` mode](#2-understanding--dev-mode)
3. [Running: basic `-dev`](#3-running-basic--dev)
4. [Binding to non-loopback (for Nomad or Docker)](#4-binding-to-non-loopback-for-nomad-or-docker)
5. [Useful flag combinations](#5-useful-flag-combinations)
6. [Ports and URLs](#6-ports-and-urls)
7. [Verifying the agent](#7-verifying-the-agent)
8. [Registering and querying services](#8-registering-and-querying-services)
9. [Using with Nomad (`-dev-consul`)](#9-using-with-nomad--dev-consul)
10. [Useful CLI commands](#10-useful-cli-commands)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites and installation

### Install Consul

```shell-session
$ brew tap hashicorp/tap
$ brew install hashicorp/tap/consul

## Verify
$ consul version
```

Or download a binary from <https://developer.hashicorp.com/consul/downloads>, unzip it, and place it on your `$PATH` (for example, `/usr/local/bin/`).

### What you need

| Requirement | Notes |
|---|---|
| macOS (Apple Silicon or Intel) | `-dev` works fully on macOS |
| No other software required | Dev mode is fully self-contained; no configuration files, no data directory needed |
| Consul binary on `$PATH` | Required if also using Nomad `-dev-connect` on Linux |

---

## 2. Understanding `-dev` mode

`-dev` is a single flag that starts a fully-functional in-memory Consul server with sensible defaults. Every setting it applies is sourced directly from `agent/config/default.go:DevSource()` and `DevConsulSource()`.

### What `-dev` sets (from source)

| Setting | Dev value | Production default | Effect |
|---|---|---|---|
| `server` | `true` | `false` | Agent runs as server (not client-only) |
| `bind_addr` | `127.0.0.1` | `0.0.0.0` | Listens only on loopback |
| `client_addr` | `127.0.0.1` | `127.0.0.1` | HTTP/DNS APIs on loopback only |
| `log_level` | `DEBUG` | `INFO` | Verbose logging |
| `ports.grpc` | `8502` | `-1` (disabled) | gRPC port enabled for service mesh and xDS |
| `ui_config.enabled` | `true` | `false` | Web UI served at `:8500/ui` |
| `connect.enabled` | `true` | `true` | Service mesh / Connect enabled; new root CA created on startup |
| `peering.enabled` | `true` | `true` | Cluster peering enabled |
| `performance.raft_multiplier` | `1` (fastest) | `5` | Raft elections as fast as possible |
| `disable_keyring_file` | `true` | `false` | Keyring not written to disk |
| `disable_anonymous_signature` | `true` | `false` | Update check signature disabled |
| `enable_debug` | `true` | `false` | Debug endpoints exposed |
| `data_dir` | not required | required | All state is in-memory only |
| Gossip timeouts | `100ms` | production values | Fast convergence for local testing |
| Raft timeouts | election `52ms`, heartbeat `35ms` | production values | Fast leader election |

### What `-dev` does not do

- **No ACLs**: ACL enforcement is off by default (`acl.default_policy = allow`). To test ACLs locally, add `-hcl 'acl { enabled = true default_policy = "deny" }'`.
- **No TLS**: all traffic is plaintext.
- **No persistence**: all state is lost when the process exits. `-dev` skips the `data_dir` requirement enforced in `builder.go:1244`.
- **No bootstrap coordination**: `bootstrap_expect > 0` is explicitly rejected in dev mode (`builder.go:1357`).

> **State is not persisted in dev mode.**
> All registered services, KV data, intentions, and ACL tokens are lost when Consul exits. This is intentional for rapid iteration.

---

## 3. Running: basic `-dev`

```shell-session
## Start Consul in dev mode (leave this terminal running)
$ consul agent -dev
```

Expected startup output:

```
==> Starting Consul agent...
           Version: '1.x.x'
          Node ID: '<generated-uuid>'
        Node name: '<your-hostname>'
       Datacenter: 'dc1' (Segment: '<all>')
           Server: true (Bootstrap: false)
      Client Addr: [127.0.0.1] (HTTP: 8500, HTTPS: -1, gRPC: 8502, gRPC-TLS: -1, DNS: 8600)
     Cluster Addr: 127.0.0.1 (LAN: 8301, WAN: 8302)
  Gossip Encryption: false
        ACL Enabled: false
==> Log data will now stream in as it occurs:
...
==> Consul agent running!
```

```shell-session
## In a second terminal — verify:
$ consul members
$ open http://localhost:8500/ui
```

---

## 4. Binding to non-loopback (for Nomad or Docker)

By default, `-dev` binds to `127.0.0.1`. If you need Consul reachable from Docker containers or from Nomad jobs, you must expose the client address:

```shell-session
## Bind the HTTP/DNS/gRPC client APIs to all interfaces
$ consul agent -dev -client=0.0.0.0
```

> **Security note:** `-client=0.0.0.0` exposes the unauthenticated Consul API to your entire local network. Only use this on a trusted network (for example, your home or office LAN), never on a public interface without ACLs enabled.

### Dynamic interface binding (from official docs)

To bind to all private IPs automatically (useful on machines with multiple network interfaces):

```shell-session
$ consul agent -dev -client '{{ GetPrivateInterfaces | join "address" " " }} {{ GetAllInterfaces | include "flags" "loopback" | join "address" " " }}'
```

To exclude Docker bridge interfaces (names starting with `br-`):

```shell-session
$ consul agent -dev -client '{{ GetPrivateInterfaces | exclude "name" "br." | join "address" " " }}'
```

---

## 5. Useful flag combinations

The following flags work on macOS. They can be stacked freely.

```shell-session
## Change the datacenter name (useful when testing multi-DC scenarios)
$ consul agent -dev -datacenter=us-east-1

## Change the node name (default is your hostname)
$ consul agent -dev -node=my-local-node

## Expose HTTP API and DNS to all interfaces (needed for Nomad integration)
$ consul agent -dev -client=0.0.0.0

## Enable ACLs with deny-by-default (test ACL policies locally)
$ consul agent -dev -hcl 'acl { enabled = true default_policy = "deny" }'

## Bootstrap an ACL master token for testing
$ consul agent -dev -hcl 'acl { enabled = true default_policy = "deny" tokens { initial_management = "root" } }'

## Change the domain (default is consul.)
$ consul agent -dev -domain=local.

## Load an extra config file on top of dev defaults
$ consul agent -dev -config-file=/path/to/extra.hcl

## Run quietly with JSON logs (useful when piping to jq)
$ consul agent -dev -log-json
```

---

## 6. Ports and URLs

| Service | Port | Protocol | URL / Notes |
|---|---|---|---|
| HTTP API + Web UI | `8500` | TCP | <http://localhost:8500> / <http://localhost:8500/ui> |
| HTTPS API | `-1` | — | Disabled in dev mode by default |
| DNS | `8600` | TCP+UDP | Query: `dig @127.0.0.1 -p 8600 consul.service.consul` |
| gRPC (xDS / service mesh) | `8502` | TCP | Enabled only in dev mode |
| gRPC-TLS | `-1` | — | Disabled in dev mode |
| Serf LAN (gossip) | `8301` | TCP+UDP | Internal cluster communication |
| Serf WAN | `8302` | TCP+UDP | Cross-datacenter gossip |
| Server RPC | `8300` | TCP | Internal Raft + RPC |
| Sidecar proxy port range | `21000`–`21255` | — | Allocated per service Connect sidecar (`agent/sidecar_service.go`) |
| `proxy_min_port`–`proxy_max_port` | `20000`–`20255` | — | Reserved for Consul's removed "managed proxy" feature. Not used by modern Envoy/Connect sidecars — those use the gRPC port above and the sidecar range below. Grep the Consul source and this range is only read back out of config, never consumed. |

---

## 7. Verifying the agent

```shell-session
## Check cluster membership
$ consul members

## Show current leader
$ consul operator raft list-peers

## Raw health check using the HTTP API
$ curl http://localhost:8500/v1/status/leader

## List all nodes
$ curl http://localhost:8500/v1/catalog/nodes | python3 -m json.tool

## Check agent info (shows all configuration values)
$ curl http://localhost:8500/v1/agent/self | python3 -m json.tool

## DNS query: resolve consul's own node
$ dig @127.0.0.1 -p 8600 consul.node.consul

## Open the Web UI
$ open http://localhost:8500/ui
```

---

## 8. Registering and querying services

Dev mode is stateless. Registrations do not survive a restart but are immediately usable for testing.

### Register a service using the CLI

```shell-session
$ consul services register -name=web -port=8080 -tag=http -tag=v1
```

### Register a service using the API

```shell-session
$ curl --request PUT \
    --data '{
      "ID": "web-1",
      "Name": "web",
      "Tags": ["http", "v1"],
      "Address": "127.0.0.1",
      "Port": 8080,
      "Check": {
        "HTTP": "http://localhost:8080/health",
        "Interval": "10s"
      }
    }' \
    http://localhost:8500/v1/agent/service/register
```

### Query a registered service

```shell-session
## Using the HTTP API
$ curl http://localhost:8500/v1/catalog/service/web | python3 -m json.tool

## Using DNS (returns A records for healthy instances)
$ dig @127.0.0.1 -p 8600 web.service.consul

## Tag-filtered DNS query (only v1 tagged instances)
$ dig @127.0.0.1 -p 8600 v1.web.service.consul

## Check service health
$ curl http://localhost:8500/v1/health/service/web?passing | python3 -m json.tool
```

### KV store

```shell-session
## Write a key
$ consul kv put config/db/host localhost

## Read it back
$ consul kv get config/db/host

## List all keys under a prefix
$ consul kv get -recurse config/

## Delete a key
$ consul kv delete config/db/host
```

### Deregister a service

```shell-session
$ curl --request PUT http://localhost:8500/v1/agent/service/deregister/web-1
```

---

## 9. Using with Nomad (`-dev-consul`)

When you run Nomad with `-dev-consul`, Nomad automatically configures workload identities pointing at the Consul agent. Consul must already be running before Nomad starts.

```shell-session
## Terminal 1: Start Consul (exposed to all interfaces so Nomad jobs can reach it)
$ consul agent -dev -client=0.0.0.0
```

```shell-session
## Terminal 2: Start Nomad with Consul workload identity defaults
$ nomad agent -dev-consul
```

With this setup:

- Nomad services are automatically registered in Consul on job submission.
- Consul service discovery is available to Nomad tasks using `${attr.consul.datacenter}` and DNS.
- Nomad workload identity JWT tokens are issued with audience `consul.io` for token-based ACL authentication.

To verify Nomad registered itself in Consul:

```shell-session
$ consul catalog services
## Should list: consul, nomad, nomad-client
```

---

## 10. Useful CLI commands

```shell-session
## Show all members in the cluster
$ consul members

## Show detailed node info
$ consul info

## List all registered services
$ consul catalog services

## List nodes providing a service
$ consul catalog nodes -service=web

## Watch a key for changes (blocks until changed)
$ consul watch -type=key -key=config/db/host

## Reload config (sends SIGHUP)
$ consul reload

## Graceful shutdown
$ consul leave

## Force-remove a failed node
$ consul force-leave <node-name>

## Snapshot the current state to a file
$ consul snapshot save backup.snap

## Debug: dump all internal state to a ZIP archive
$ consul debug -output=/tmp/consul-debug -duration=5s -interval=1s
```

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `bind: address already in use` on port `8500`/`8600`/`8300` | Another Consul process is running | `pkill -f "consul agent"` or `lsof -i :8500` to identify and stop the conflicting process |
| `Error querying agent` from `consul members` | Consul not running or not on `127.0.0.1:8500` | Check that `consul agent -dev` is running; verify with `curl http://localhost:8500/v1/status/leader` |
| Services not reachable from Docker containers | Consul bound only to loopback | Restart with `-client=0.0.0.0` so containers can reach the API |
| DNS not resolving (`dig` returns NXDOMAIN) | Wrong port or query format | Dev mode uses port `8600`, not `53`. Use: `dig @127.0.0.1 -p 8600 <service>.service.consul` |
| All registered services lost after restart | Dev mode has no persistence | Expected. Dev mode is in-memory only. Re-register services after restart, or use `-data-dir` for persistence (exits dev mode). |
| `bootstrap_expect > 0 not allowed in dev mode` | Tried to combine `-dev` with `-bootstrap-expect` | Remove `-bootstrap-expect`. Dev mode bootstraps automatically as a single-node cluster. |
| Nomad jobs can't find Consul services | `consul agent -dev` started without `-client=0.0.0.0` | Nomad tasks run in a separate network context. Consul must be reachable on a non-loopback address. |
| gRPC port `8502` already in use | Another service using `8502` | Use `-hcl 'ports { grpc = 8503 }'` to override |

### Quick health check script

```shell-session
$ bash << 'EOF'
echo "=== Consul status ==="
consul members 2>/dev/null || echo "Consul not reachable on :8500"
echo ""
echo "=== Leader check ==="
curl -s http://localhost:8500/v1/status/leader 2>/dev/null || echo "HTTP API not responding"
echo ""
echo "=== Port check ==="
lsof -i :8500 -i :8600 -i :8300 -i :8301 -i :8502 2>/dev/null | grep LISTEN
echo ""
echo "=== DNS check ==="
dig @127.0.0.1 -p 8600 consul.service.consul +short 2>/dev/null || echo "DNS not responding on :8600"
EOF
```
