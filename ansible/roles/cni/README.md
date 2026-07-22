# CNI (Container Network Interface) Role

## Description

The CNI role installs Container Network Interface (CNI) plugins required for Nomad's container networking capabilities. These plugins enable advanced networking features like network isolation, port mapping, and bridge networking for containerized workloads.

## Features

- Downloads and installs CNI plugins from GitHub releases
- Installs plugins to `/opt/cni/bin`
- Creates CNI configuration directory
- Supports custom CNI configurations
- Ubuntu-specific (conditional execution)

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `cni_plugins_version` | string | `1.9.1` | Version of CNI plugins to install |
| `cni_plugins_path` | string | `/opt/cni/bin` | Installation directory for CNI binaries |
| `cni_plugins_config_path` | string | `/opt/cni/config` | Directory for CNI configuration files |
| `cni_configs` | list | `[]` | List of CNI configuration files to create |
| `consul_cni_enabled` | bool | `false` | Install the separate `consul-cni` plugin, required only for Nomad's Consul Connect *transparent proxy* mode |
| `consul_cni_version` | string | `1.6.2` | Version of `consul-cni` to install |

## CNI plugins included

The installation includes standard CNI plugins:
- bridge
- dhcp
- host-local
- loopback
- portmap
- ptp
- vlan
- And more...

## consul-cni (transparent proxy only)

`consul-cni` is a separate, single-binary plugin published at
[releases.hashicorp.com/consul-cni](https://releases.hashicorp.com/consul-cni),
distinct from the `containernetworking/plugins` bundle above. It is **not**
needed for plain bridge-mode Consul service mesh using explicit `upstreams`
blocks (this repo's default mesh job specs) — only for Nomad's
`transparent_proxy {}` mode, which uses it to install `iptables` traffic
redirection rules into each allocation's network namespace at CNI setup
time. Installed into the same `cni_plugins_path` as the standard plugins,
conditional on `consul_cni_enabled: true` (set by the service-mesh playbook,
not the base client playbook — see
`_context/wiki/transparent-proxy-enablement-plan.md`).

## Usage

### In Playbooks

This role is used **only in the client playbook** since clients run containerized workloads:

**Client Playbook** (`playbooks/nomad_clients.yaml`):
```yaml
- role: cni
  when: ansible_distribution == "Ubuntu"
```

### Not Used In

- Server playbook (servers don't run workloads)

## Dependencies

- Ubuntu operating system (role is conditional)
- Internet access to download CNI plugins from GitHub

## Example

```yaml
- hosts: clients
  roles:
    - role: cni
      when: ansible_distribution == "Ubuntu"
```

### With Custom Configuration

```yaml
- hosts: clients
  roles:
    - role: cni
      vars:
        cni_configs:
          - name: "10-bridge.conf"
            content: |
              {
                "cniVersion": "1.0.0",
                "name": "bridge",
                "type": "bridge",
                "bridge": "cni0",
                "isGateway": true,
                "ipMasq": true,
                "ipam": {
                  "type": "host-local",
                  "subnet": "10.22.0.0/16"
                }
              }
```

## System requirements

- Ubuntu (role checks `ansible_distribution`)
- Sufficient disk space in `/opt/cni/bin` (~50MB)
- Network access to GitHub releases

## Notes

- CNI plugins are required for Nomad's `bridge` network mode
- Without CNI plugins, only `host` network mode is available
- The role is idempotent - safe to run multiple times
- Plugins are downloaded from official CNI GitHub releases

## Troubleshooting

### Plugins not found
If Nomad reports CNI plugins not found:
```bash
# Verify installation
ls -la /opt/cni/bin/

# Check Nomad client configuration
nomad agent-info | grep cni
```

### Network issues
If containers can't communicate:
```bash
# Check bridge interface
ip link show cni0

# Verify iptables rules
sudo iptables -t nat -L -n -v
```

## Author

Created for nomad-infra project