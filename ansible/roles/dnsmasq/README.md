# dnsmasq Role

Installs and configures **dnsmasq** on every cluster node to forward `.global`
DNS queries to the local Consul agent (port 8600), enabling Consul service
discovery via DNS for all processes on the host.

## What this role does

1. Installs the `dnsmasq` package
2. Disables the `systemd-resolved` DNS stub listener so dnsmasq can bind to port 53
3. Writes `/etc/dnsmasq.conf` — main configuration (listens on `127.0.0.1`)
4. Writes `/etc/dnsmasq.d/10-consul` — forwards `.global` domain to `127.0.0.1:8600`
5. Optionally rewrites `/etc/resolv.conf` to use `127.0.0.1` as the system resolver
6. Enables and starts the `dnsmasq` service

## OS-level changes

The role makes three changes to the operating system that together redirect all DNS resolution through dnsmasq.

### 1. Disables systemd-resolved's stub listener

On Ubuntu/Debian, `systemd-resolved` runs a DNS stub listener on `127.0.0.53:53` by default, which blocks dnsmasq from binding to port 53. The role drops a drop-in override file:

```
/etc/systemd/resolved.conf.d/no-stub.conf
  [Resolve]
  DNSStubListener=no
```

`systemd-resolved` is then restarted. It continues to function as a system caching resolver but releases port 53 so dnsmasq can own it. This step is skipped when `dnsmasq_disable_resolved_stub: false`.

### 2. Writes dnsmasq configuration files

- `/etc/dnsmasq.conf` — binds to each address in `dnsmasq_listen_addresses` (`["127.0.0.1"]` role default; `group_vars/all.yaml` sets `["127.0.0.1", "172.17.0.1"]` so Docker task driver containers can reach dnsmasq at the bridge gateway), sets `no-resolv` (ignores `/etc/resolv.conf` for upstream), explicitly lists upstream DNS servers (AWS VPC resolver `169.254.169.253` by default), configures caching (1000 entries), and sets `domain-needed` and `bogus-priv` as safety guards.
- `/etc/dnsmasq.d/10-consul` — the forwarding rule that sends all `.global` queries to the local Consul agent DNS port:

  ```
  server=/global/127.0.0.1#8600
  ```

  Plus `rev-server=` entries for RFC 1918 ranges so that reverse DNS (PTR) lookups for private IPs are also forwarded to Consul.

### 3. Replaces `/etc/resolv.conf`

Writes a minimal file with a single entry:

```
nameserver 127.0.0.1
```

This makes every process on the host — the kernel resolver, `glibc`, applications, and Nomad job tasks — use dnsmasq as their DNS resolver. This step is skipped when `dnsmasq_update_resolv_conf: false`.

## DNS resolution flow

Host processes and Docker task driver containers take different paths to reach dnsmasq:

```
Host process (shell, Nomad agent)        Docker container (Nomad job)
        │                                         │
        │  nameserver 127.0.0.1                   │  dns.servers = ["172.17.0.1"]
        ▼                                         ▼
dnsmasq 127.0.0.1:53              dnsmasq 172.17.0.1:53
        │                                         │
        └─────────────── same dnsmasq process ────┘
                                  │
               ┌──────────────────┴──────────────────┐
               │ .global domain                       │ all other queries
               ▼                                      ▼
  Consul agent DNS (127.0.0.1:8600)      AWS VPC resolver (169.254.169.253)
  Returns IPs from Consul catalog
```

## Why dnsmasq is required for Consul service discovery

Consul's built-in DNS listener runs on port **8600**, not 53. Standard DNS libraries always query port 53; only privileged processes can bind to or directly query non-standard ports.

Without dnsmasq (or an equivalent forwarder), every application and Nomad job would need to hardcode `127.0.0.1:8600` as its resolver. That is non-standard and does not work with tools that rely on the system resolver.

With dnsmasq in place, standard DNS lookups such as `redis.service.global`, `nomad.service.global`, and `_http._tcp.api.service.global` (SRV records) work from the shell, from Nomad `template` blocks, or from any process inside a container with host networking — without any application-level changes.

The dnsmasq playbook (`ansible/playbooks/dnsmasq.yaml`) is a prerequisite for any scenario that uses Consul DNS-based service discovery and is included automatically in `deploy_consul_nomad_sd.yaml`.

## The Docker task driver DNS problem

### Root cause

When Nomad runs a task with the Docker task driver, Docker places the container
in its own network namespace. From inside that container:

- `127.0.0.1` is the container's own loopback — **not** the host's.
- The host is reachable at the Docker bridge gateway, which defaults to
  `172.17.0.1` (the `docker0` interface on the host).

If dnsmasq is configured with `listen-address=127.0.0.1` and `bind-interfaces`,
it only accepts connections on the loopback interface. It does **not** listen on
`172.17.0.1`, so any Nomad job that sets `dns { servers = ["172.17.0.1"] }` sends
DNS queries to an address with nothing on port 53 — queries are silently dropped.

### The fix

`dnsmasq_listen_addresses` is a list so dnsmasq can bind to both interfaces. The
template iterates over the list:

```
{% for addr in dnsmasq_listen_addresses %}
listen-address={{ addr }}
{% endfor %}
bind-interfaces
```

`group_vars/all.yaml` sets the project-wide default to both addresses since all
Nomad clients in this project use the Docker task driver:

```yaml
dnsmasq_listen_addresses:
  - "127.0.0.1"
  - "172.17.0.1"
```

With this configuration, `dns { servers = ["172.17.0.1"] }` in Nomad job network
blocks is correct — dnsmasq listens on that interface.

## Caveats

- `172.17.0.1` is Docker's default bridge subnet gateway. If Docker is configured
  with a non-default `--bip` address in `/etc/docker/daemon.json`, update
  `dnsmasq_listen_addresses` in `group_vars/all.yaml` to match.
- This exposes the dnsmasq DNS port on the `docker0` interface. Docker's default
  bridge is not reachable from outside the host, so the exposure is local-only.
  If `docker0` is bridged to a physical interface, review the security implications.
- Nomad bridge network mode (CNI) uses a different DNS injection mechanism via
  the Consul Connect sidecar. The `dnsmasq_listen_addresses` configuration applies
  only to containers running in Docker's default bridge network (the Nomad Docker
  task driver default).

## Prerequisites

- A Consul agent (server or client) must be running on each node and serving
  DNS on port 8600.
- The Consul role must be deployed before this role runs.

## Key variables

| Variable | Default | Description |
|---|---|---|
| `dnsmasq_version` | `2.93` | dnsmasq package version to install |

| Variable | Default | Description |
|----------|---------|-------------|
| `dnsmasq_upstream_dns_servers` | `["169.254.169.253"]` | Upstream resolvers for non-.global queries |
| `consul_dns_port` | `8600` | Consul agent DNS port |
| `dnsmasq_listen_addresses` | `["127.0.0.1"]` | Addresses dnsmasq binds to. Add `"172.17.0.1"` when using the Nomad Docker task driver. |
| `dnsmasq_cache_size` | `1000` | DNS cache entry count |
| `dnsmasq_disable_resolved_stub` | `true` | Disable systemd-resolved stub listener |
| `dnsmasq_update_resolv_conf` | `true` | Rewrite `/etc/resolv.conf` |
| `dnsmasq_consul_rev_networks` | RFC 1918 blocks | Networks for Consul reverse DNS |

Refer to [`defaults/main.yaml`](defaults/main.yaml) for the full variable reference.

## Validation

After deployment, verify DNS forwarding is working:

```bash
# Resolve Consul's own service address
host consul.service.global

# Resolve a registered Nomad service (replace with your service name)
host nomad.service.global
```

## References

- [Enable DNS forwarding — dnsmasq](https://developer.hashicorp.com/consul/docs/manage/dns/forwarding/enable#dnsmasq)
