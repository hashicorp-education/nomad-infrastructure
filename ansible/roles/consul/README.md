# consul

Ansible role to install and configure a [Consul](https://www.consul.io/) v2.x agent (server or client) on an Ubuntu/Debian host.

## Requirements

- Ansible 2.14+
- `hashicorp_release` role (bundled in this repo) for binary installation
- `geerlingguy.docker` role installed via `requirements.yaml` (Docker must be present before Consul starts)
- The `community.crypto` collection for TLS certificate operations when `consul_tls_enabled: true`

## Role variables

Key variables (see `defaults/main.yaml` for the full list and defaults):

| Variable | Default | Description |
|---|---|---|
| `consul_binary_version` | `2.0.1` | Consul release to install |
| `consul_server_enabled` | `false` | Run this node as a server agent |
| `consul_server_bootstrap_expect` | `3` | Expected number of servers in the cluster |
| `consul_client_enabled` | `false` | Not used directly; set `consul_server_enabled: false` for a client agent |
| `consul_datacenter` | `dc1` | Datacenter name |
| `consul_bind_addr` | `{{ ansible_facts['default_ipv4']['address'] }}` | Address Consul binds to |
| `consul_client_addr` | `0.0.0.0` | Address Consul listens on for HTTP/DNS/gRPC |
| `consul_cloud_auto_join_enabled` | `false` | Enable AWS cloud auto-join via `retry_join` |
| `consul_cloud_auto_join_tag_key` | `AutoJoinRole` | EC2 tag key for cloud auto-join |
| `consul_cloud_auto_join_tag_value` | `server` | EC2 tag value for cloud auto-join |
| `consul_acl_enabled` | `false` | Enable ACLs |
| `consul_tls_enabled` | `false` | Enable TLS (requires certs in `consul_tls_dir`) |
| `consul_gossip_encryption_enabled` | `false` | Enable gossip encryption |
| `consul_gossip_encryption_key` | `""` | Base64 gossip key (generate with `consul keygen`) |
| `consul_connect_enabled` | `false` | Enable Consul Connect (service mesh) |

## Inventory groups

This role targets the Terraform-generated inventory groups directly:
- `[servers]` — hosts that run as Consul servers (`consul_server_enabled: true`)
- `[clients]` — hosts that run as Consul clients (`consul_server_enabled: false`)

## TLS

When `consul_tls_enabled: true`, certificates must exist at:
- `{{ consul_tls_dir }}/ca.pem`
- `{{ consul_tls_dir }}/consul.pem`
- `{{ consul_tls_dir }}/consul-key.pem`

Use the `tls` role (bundled in this repo) to generate a self-signed CA and node certificates on the control host, then distribute them via the `helper` role as shown in `consul_servers.yaml`.

## Cloud auto-join

Set `consul_cloud_auto_join_enabled: true` and ensure the EC2 instances carry the tag `AutoJoinRole=server`. The IAM instance profile created by Terraform already grants `ec2:DescribeInstances`.

## Usage

Refer to the top-level playbooks:
- `ansible/consul_servers.yaml` — configures the `[servers]` group as Consul servers
- `ansible/consul_clients.yaml` — configures the `[clients]` group as Consul clients

Run the full cluster setup via:
```bash
ansible-playbook -i inventory.ini consul_servers.yaml
ansible-playbook -i inventory.ini consul_clients.yaml
```

## Ports

| Port | Protocol | Purpose |
|---|---|---|
| 8300 | TCP | Server RPC |
| 8301 | TCP/UDP | Serf LAN gossip |
| 8302 | TCP/UDP | Serf WAN gossip |
| 8500 | TCP | HTTP API / UI |
| 8502 | TCP | gRPC |
| 8600 | TCP/UDP | DNS |
