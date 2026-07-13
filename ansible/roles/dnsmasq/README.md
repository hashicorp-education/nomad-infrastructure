# dnsmasq Role

Installs and configures **dnsmasq** on every cluster node to forward `.consul`
DNS queries to the local Consul agent (port 8600), enabling Consul service
discovery via DNS for all processes on the host.

## What this role does

1. Installs the `dnsmasq` package
2. Disables the `systemd-resolved` DNS stub listener so dnsmasq can bind to port 53
3. Writes `/etc/dnsmasq.conf` — main configuration (listens on `127.0.0.1`)
4. Writes `/etc/dnsmasq.d/10-consul` — forwards `.consul` domain to `127.0.0.1:8600`
5. Optionally rewrites `/etc/resolv.conf` to use `127.0.0.1` as the system resolver
6. Enables and starts the `dnsmasq` service

## DNS resolution flow

```
Application
    │
    │  DNS query for service.consul
    ▼
dnsmasq (127.0.0.1:53)
    │
    ├── .consul queries ──►  Consul agent DNS (127.0.0.1:8600)
    │
    └── all other queries ──►  Upstream DNS (for example, 169.254.169.253 on AWS)
```

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
| `dnsmasq_upstream_dns_servers` | `["169.254.169.253"]` | Upstream resolvers for non-.consul queries |
| `consul_dns_port` | `8600` | Consul agent DNS port |
| `dnsmasq_listen_address` | `127.0.0.1` | Address dnsmasq binds to |
| `dnsmasq_cache_size` | `1000` | DNS cache entry count |
| `dnsmasq_disable_resolved_stub` | `true` | Disable systemd-resolved stub listener |
| `dnsmasq_update_resolv_conf` | `true` | Rewrite `/etc/resolv.conf` |
| `dnsmasq_consul_rev_networks` | RFC 1918 blocks | Networks for Consul reverse DNS |

Refer to [`defaults/main.yaml`](defaults/main.yaml) for the full variable reference.

## Validation

After deployment, verify DNS forwarding is working:

```bash
# Resolve Consul's own service address
host consul.service.consul

# Resolve a registered Nomad service (replace with your service name)
host nomad.service.consul
```

## References

- [Enable DNS forwarding — dnsmasq](https://developer.hashicorp.com/consul/docs/manage/dns/forwarding/enable#dnsmasq)
