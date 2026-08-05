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
| `consul_binary_version` | `2.0.2` | Consul release to install |
| `consul_edition` | `oss` | `oss` or `enterprise`. When `enterprise`, installs the `+ent` release artifact and renders `license_path` at the top level of `consul.hcl`; requires the calling playbook to distribute a license file to `{{ consul_license_dir }}/license.hclic`. Required on every agent (servers and clients) |
| `consul_server_enabled` | `false` | Run this node as a server agent |
| `consul_server_bootstrap_expect` | `3` | Expected number of servers in the cluster |
| `consul_client_enabled` | `false` | Not used directly; set `consul_server_enabled: false` for a client agent |
| `consul_datacenter` | `dc1` | Datacenter name |
| `consul_bind_addr` | `{{ ansible_facts['default_ipv4']['address'] }}` | Address Consul binds to |
| `consul_client_addr` | `0.0.0.0` | Address Consul listens on for HTTP/DNS/gRPC when TLS is disabled |
| `consul_addr_http` | `127.0.0.1` | Address for the plain-HTTP API when TLS is enabled (loopback only, for local automation and Nomad's local `consul {}` integration) |
| `consul_addr_https` | `0.0.0.0` | Address for the HTTPS API when TLS is enabled |
| `consul_cloud_auto_join_enabled` | `false` | Enable AWS cloud auto-join via `retry_join` |
| `consul_cloud_auto_join_tag_key` | `AutoJoinRole` | EC2 tag key for cloud auto-join |
| `consul_cloud_auto_join_tag_value` | `server` | EC2 tag value for cloud auto-join |
| `consul_acl_enabled` | `false` | Enable ACLs |
| `consul_acl_default_policy` | `deny` | Default ACL policy when ACLs are enabled |
| `consul_acl_enable_token_persistence` | `true` | Persist tokens to the agent data dir so they survive restarts |
| `consul_acl_agent_token` | `""` | Per-node agent token written into `acl.tokens.agent`. Set by `consul_dns_token.yaml` to a node-identity token for each client. Empty by default — the `tokens {}` block is omitted when both agent and DNS tokens are unset. |
| `consul_acl_dns_token` | `""` | Shared DNS token written into `acl.tokens.dns`. Set by `consul_dns_token.yaml`. Allows the Consul agent to answer DNS queries when ACL default-deny is active. Empty by default. |
| `consul_tls_enabled` | `true` | Enable TLS (requires certs in `consul_tls_dir`). Splits access into a loopback plain-HTTP listener (`consul_addr_http`) and an external HTTPS listener (`consul_addr_https`); the `tls{}` stanza is split into `https{}` (API, `verify_incoming: false`) and `internal_rpc{}` (full mTLS) |
| `consul_gossip_encryption_enabled` | `false` | Enable gossip encryption |
| `consul_gossip_encryption_key` | `""` | Base64 gossip key (generate with `consul keygen`) |
| `consul_connect_enabled` | `false` | Enable Consul Connect (service mesh) |

## Inventory groups

This role targets the Terraform-generated inventory groups directly:
- `[servers]` — hosts that run as Consul servers (`consul_server_enabled: true`)
- `[clients]` — hosts that run as Consul clients (`consul_server_enabled: false`)

## TLS

TLS is enabled by default (`consul_tls_enabled: true`). Certificates must exist at:
- `{{ consul_tls_dir }}/ca.pem`
- `{{ consul_tls_dir }}/consul.pem`
- `{{ consul_tls_dir }}/consul-key.pem`

Use the `tls` role (bundled in this repo) to generate a self-signed CA and node certificates on the control host, then distribute them via the `helper` role as shown in `consul_servers.yaml`.

When TLS is enabled, Consul uses a hybrid access model:
- Plain HTTP stays on `consul_addr_http` (default `127.0.0.1:8500`, loopback only) for local automation and Nomad's local `consul {}` integration.
- HTTPS is exposed on `consul_addr_https:consul_port_https` (default `0.0.0.0:8443`).

Client-certificate verification is disabled on the HTTPS API (`verify_incoming: false` in the `tls.https{}` stanza) — security relies on ACLs, not mTLS, for API access. Full mutual TLS (`verify_incoming`/`verify_outgoing`/`verify_server_hostname: true`) is enforced on the `tls.internal_rpc{}` stanza used for server-to-server traffic. Set `consul_tls_enabled: false` to disable TLS entirely.

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
| 8500 | TCP | HTTP API / UI (loopback only when TLS is enabled) |
| 8443 | TCP | HTTPS API / UI (when TLS is enabled) |
| 8502 | TCP | gRPC |
| 8600 | TCP/UDP | DNS |
