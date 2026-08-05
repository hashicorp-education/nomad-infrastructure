# Common Role

## Description

The common role provides base system configuration for all hosts in the Nomad cluster. It handles essential system setup tasks that should be applied to every server and client node.

## Features

- Installs common system packages
- Configures NTP for time synchronization
- Sets hostname based on inventory
- Updates system packages
- Performs basic system hardening

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `common_packages` | list | Refer to defaults | List of packages to install |
| `common_hostname` | string | `""` | Hostname to set for the system |

### Default packages

- curl
- wget
- unzip
- jq
- git
- vim
- htop
- net-tools
- dnsutils
- software-properties-common
- nano
- ntp

## Usage

### In Playbooks

This role is used in both server and client playbooks:

**Server Playbook** (`playbooks/nomad_servers.yaml`):
```yaml
- role: common
  vars:
    common_hostname: "{{ inventory_hostname }}"
```

**Client Playbook** (`playbooks/nomad_clients.yaml`):
```yaml
- role: common
  vars:
    common_hostname: "{{ inventory_hostname }}"
```

## Dependencies

None

## Example

```yaml
- hosts: all
  roles:
    - role: common
      vars:
        common_hostname: "nomad-server-1"
```

## Notes

- This role should be applied before any other roles
- Ensures consistent base configuration across all nodes
- Time synchronization is critical for distributed systems like Nomad

## Author

Created for nomad-infra project