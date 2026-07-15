# dnsmasq, Consul DNS, and Docker task driver DNS

## Summary

This page documents how dnsmasq integrates with the OS for Consul service
discovery, the specific failure mode when Nomad jobs use the Docker task
driver, and the fix applied to this project.

## How dnsmasq integrates with the OS

The dnsmasq role makes three OS-level changes that together redirect all DNS
resolution through dnsmasq on every cluster node.

### 1. Disables systemd-resolved's stub listener

Ubuntu/Debian systems run `systemd-resolved` with a DNS stub listener on
`127.0.0.53:53` by default. This occupies the port dnsmasq needs. The role
drops a drop-in override:

```
/etc/systemd/resolved.conf.d/no-stub.conf
  [Resolve]
  DNSStubListener=no
```

`systemd-resolved` is restarted but keeps running as a caching resolver — it
just stops owning port 53. Controlled by `dnsmasq_disable_resolved_stub`
(default `true`).

### 2. Writes dnsmasq configuration files

- `/etc/dnsmasq.conf` — binds to each address in `dnsmasq_listen_addresses`,
  sets `no-resolv` (ignores `/etc/resolv.conf` for upstream), lists upstream
  DNS servers (AWS VPC resolver `169.254.169.253` by default), configures
  caching (1000 entries), and sets `domain-needed` + `bogus-priv` as safety
  guards.
- `/etc/dnsmasq.d/10-consul` — the forwarding rule:
  ```
  server=/consul/127.0.0.1#8600
  ```
  Plus `rev-server=` entries for RFC 1918 ranges so PTR lookups for private
  IPs are also forwarded to Consul.

### 3. Replaces `/etc/resolv.conf`

Writes:
```
nameserver 127.0.0.1
```

This makes every process on the host — including the kernel resolver, `glibc`,
and Nomad job tasks in host-network mode — use dnsmasq as their DNS resolver.
Controlled by `dnsmasq_update_resolv_conf` (default `true`).

## Why dnsmasq is required for Consul service discovery

Consul's built-in DNS listener runs on port **8600**, not 53. Standard DNS
libraries always query port 53. Without dnsmasq, every application and Nomad
job would need to hardcode `127.0.0.1:8600`, which does not work with any tool
that relies on the system resolver.

With dnsmasq in place, lookups like `redis.service.consul`,
`nomad.service.consul`, and `_http._tcp.api.service.consul` (SRV records) work
from the shell, from Nomad `template` blocks, and from any process using the
system resolver — with no application-level changes.

The `ansible/playbooks/dnsmasq.yaml` playbook applies to `hosts: all` and is
included automatically in `deploy_consul_nomad_sd.yaml`.

## The Docker task driver DNS problem

### Root cause

When Nomad runs a task with the Docker task driver, Docker places the container
in its own network namespace. From inside that container:

- `127.0.0.1` is the container's own loopback — **not** the host's.
- The host is reachable at the Docker bridge gateway, which defaults to
  `172.17.0.1` (the `docker0` interface on the host).

The original dnsmasq role bound dnsmasq with:
```
listen-address=127.0.0.1
bind-interfaces
```

Because of `bind-interfaces`, dnsmasq only accepted connections on the
loopback interface. It did **not** listen on `172.17.0.1`. Any Nomad job that
set `dns { servers = ["172.17.0.1"] }` was sending DNS queries to an address
that had nothing listening on port 53 — queries were silently dropped.

### The fix

`dnsmasq_listen_address` (a single string) was replaced with
`dnsmasq_listen_addresses` (a list). The template now iterates:

```
{% for addr in dnsmasq_listen_addresses %}
listen-address={{ addr }}
{% endfor %}
bind-interfaces
```

`group_vars/all.yaml` sets the project-wide default to both addresses since
all Nomad clients in this project use the Docker task driver:

```yaml
dnsmasq_listen_addresses:
  - "127.0.0.1"
  - "172.17.0.1"
```

With this change, `dns { servers = ["172.17.0.1"] }` in Nomad job network
blocks is correct — dnsmasq is now listening on that interface.

## DNS resolution flow (after fix)

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
               │ .consul domain                       │ all other queries
               ▼                                      ▼
  Consul agent DNS (127.0.0.1:8600)      AWS VPC resolver (169.254.169.253)
  Returns IPs from Consul catalog
```

## Files changed

| File | Change |
|------|--------|
| `ansible/roles/dnsmasq/defaults/main.yaml` | `dnsmasq_listen_address` (str) → `dnsmasq_listen_addresses` (list) |
| `ansible/roles/dnsmasq/templates/dnsmasq.conf.j2` | Iterates over `dnsmasq_listen_addresses` list |
| `ansible/roles/dnsmasq/meta/argument_specs.yaml` | Updated type to `list`, expanded description |
| `ansible/roles/dnsmasq/README.md` | Added OS-level changes, DNS resolution flow, and Docker driver sections |
| `ansible/group_vars/all.yaml` | Added `dnsmasq_listen_addresses` with both loopback and Docker bridge addresses |

## Caveats

- `172.17.0.1` is Docker's default bridge subnet gateway. If Docker is
  configured with a non-default `--bip` in `/etc/docker/daemon.json`, update
  `dnsmasq_listen_addresses` in `group_vars/all.yaml` to match.
- This setup exposes the dnsmasq DNS port on the `docker0` interface. Docker's
  default bridge is not reachable from outside the host, so the exposure is
  local-only. If `docker0` is bridged to a physical interface, review the
  security implications.
- Nomad bridge network mode (CNI) uses a different DNS injection mechanism
  (Consul Connect sidecar). The `dnsmasq_listen_addresses` fix applies only to
  containers running in Docker's default bridge network (the Nomad Docker task
  driver default).
