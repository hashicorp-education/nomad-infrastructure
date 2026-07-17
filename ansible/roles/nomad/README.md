# Nomad Role

## Description

The nomad role installs and configures HashiCorp Nomad v2.0.4 on both server and client nodes. It handles binary installation, configuration file generation, systemd service setup, and initial service startup.

## Features

- Installs Nomad binary via hashicorp_release role
- Creates configuration directories and data directories
- Generates Nomad configuration from Jinja2 templates
- Sets up systemd service for automatic startup
- Supports both server and client modes
- Configures cloud auto-join for AWS
- Enables telemetry and logging
- Handles ACL and TLS configuration
- Supports Consul integration via `consul {}` block (Workload Identity, Nomad 1.7+)

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `nomad_user` | string | `root` | User to run Nomad service |
| `nomad_group` | string | `root` | Group to run Nomad service |
| `nomad_binary_version` | string | `2.0.4` | Nomad version to install |
| `nomad_config_dir` | string | `/etc/nomad.d` | Configuration directory |
| `nomad_data_dir` | string | `/opt/nomad/data` | Data directory |
| `nomad_plugin_dir` | string | `/opt/nomad/plugins` | Plugin directory |
| `nomad_service_name` | string | `nomad` | Systemd service name |
| `nomad_server_enabled` | bool | `false` | Enable server mode |
| `nomad_server_bootstrap_expect` | int | `3` | Expected number of servers |
| `nomad_client_enabled` | bool | `false` | Enable client mode |
| `nomad_client_servers` | list | `[]` | List of server addresses |
| `nomad_acl_enabled` | bool | `false` | Enable ACL system |
| `nomad_tls_enabled` | bool | `true` | Enable TLS for Nomad HTTP and RPC. Nomad has no loopback exception — when enabled, both layers are TLS-only |
| `nomad_telemetry_enabled` | bool | `false` | Enable telemetry |
| `nomad_telemetry_prometheus_metrics` | bool | `false` | Enable Prometheus metrics |
| `nomad_log_level` | string | `INFO` | Logging level |
| `nomad_log_file` | string | `/var/log/nomad.log` | Log file path |
| `nomad_log_include_location` | bool | `false` | Include source location in logs |
| `nomad_enable_debug` | bool | `false` | Enable debug mode |
| `nomad_cloud_auto_join_enabled` | bool | `false` | Enable AWS cloud auto-join |
| `nomad_cloud_auto_join_tag_key` | string | `AutoJoinRole` | AWS tag key for auto-join |
| `nomad_cloud_auto_join_tag_value` | string | `server` | AWS tag value for auto-join |
| `nomad_consul_integration_enabled` | bool | `false` | Enable Consul integration (`consul {}` block); set `true` after running `consul_nomad_service_discovery.yaml` |
| `nomad_consul_workload_identity_enabled` | bool | `false` | Add `service_identity` and `task_identity` blocks in the `consul {}` section (Nomad servers only, requires Nomad 1.7+); set `true` after running `consul_nomad_workload_identity.yaml` |
| `nomad_consul_address` | string | `127.0.0.1:8500` | Consul agent address |
| `nomad_consul_agent_token` | string | `""` | Consul ACL token for Nomad agent operations |
| `nomad_client_use_consul_token` | bool | `false` | When `true`, Nomad clients pass the Consul agent token to `template {}` blocks via `client.template.use_client_consul_token`. Set by `nomad_clients.yaml` when using service discovery without workload identity. |
| `nomad_consul_service_identity_aud` | string | `consul.io` | Audience for service workload identities |
| `nomad_consul_service_identity_ttl` | string | `1h` | TTL for service workload identity tokens |
| `nomad_consul_task_identity_aud` | string | `consul.io` | Audience for task workload identities |
| `nomad_consul_task_identity_ttl` | string | `1h` | TTL for task workload identity tokens |

## Directory structure

The role creates the following directories:
```
/etc/nomad.d/          # Configuration files
/opt/nomad/data/       # Nomad data directory
/opt/nomad/plugins/    # Plugin directory
/var/log/              # Log directory
```

## Usage

### In Playbooks

**Server Playbook** (`nomad_servers.yaml`):
```yaml
- role: nomad
  vars:
    nomad_server_enabled: true
    nomad_server_bootstrap_expect: "{{ groups['servers'] | length }}"
    nomad_client_enabled: false
    nomad_cloud_auto_join_enabled: true
    nomad_cloud_auto_join_tag_key: "AutoJoinRole"
    nomad_cloud_auto_join_tag_value: "server"
```

**Client Playbook** (`nomad_clients.yaml`):
```yaml
- role: nomad
  vars:
    nomad_server_enabled: false
    nomad_client_enabled: true
    nomad_cloud_auto_join_enabled: true
    nomad_cloud_auto_join_tag_key: "AutoJoinRole"
    nomad_cloud_auto_join_tag_value: "server"
```

**With Consul integration** (as run by `playbooks/consul_nomad_service_discovery.yaml`):
```yaml
- role: nomad
  vars:
    nomad_consul_integration_enabled: true
    nomad_consul_agent_token: "{{ lookup('file', inventory_dir + '/tokens/nomad-consul-server-secret-id.txt') }}"
```

## Configuration templates

The role uses Jinja2 templates to generate configuration:
- `templates/nomad.hcl.j2` - Main Nomad configuration
- `templates/nomad.service.j2` - Systemd service file

## Server mode

When `nomad_server_enabled: true`:
- Configures Nomad as a server
- Sets bootstrap_expect for cluster formation
- Enables server-specific features
- Configures cloud auto-join for server discovery

## Client mode

When `nomad_client_enabled: true`:
- Configures Nomad as a client
- Enables Docker driver (if Docker is installed)
- Configures network interface
- Sets up resource allocation
- Configures cloud auto-join to find servers

## Cloud auto-join (AWS)

When enabled, Nomad automatically discovers cluster members using AWS tags:

```yaml
nomad_cloud_auto_join_enabled: true
nomad_cloud_auto_join_tag_key: "AutoJoinRole"
nomad_cloud_auto_join_tag_value: "server"
```

This requires:
- IAM instance profile with EC2 describe permissions
- Instances tagged with the specified key/value

## Handlers

The role includes handlers for:
- `Reload systemd` - Reloads systemd daemon
- `Enable nomad` - Enables Nomad service
- `Restart nomad` - Restarts Nomad service

## Dependencies

- `hashicorp_release` role (included automatically)
- Docker (for client nodes running containers)
- CNI plugins (for client nodes with bridge networking)

## Example Configurations

### Basic server

```yaml
- hosts: servers
  roles:
    - role: nomad
      vars:
        nomad_server_enabled: true
        nomad_server_bootstrap_expect: 3
```

### Basic client

```yaml
- hosts: clients
  roles:
    - role: nomad
      vars:
        nomad_client_enabled: true
```

### Server with ACLs

```yaml
- hosts: servers
  roles:
    - role: nomad
      vars:
        nomad_server_enabled: true
        nomad_server_bootstrap_expect: 3
        nomad_acl_enabled: true
```

### Client with debug logging

```yaml
- hosts: clients
  roles:
    - role: nomad
      vars:
        nomad_client_enabled: true
        nomad_log_level: "DEBUG"
        nomad_enable_debug: true
```

## Post-installation

After the role completes:

1. **Verify Service Status**:
```bash
sudo systemctl status nomad
```

2. **Check Cluster Members** (on servers):
```bash
nomad server members
```

3. **Check Node Status** (on clients):
```bash
nomad node status
```

4. **View Logs**:
```bash
sudo journalctl -u nomad -f
```

## Telemetry

Prometheus metrics are exposed at:
```
https://<nomad-address>:4646/v1/metrics?format=prometheus
```
(`http://` when `nomad_tls_enabled: false`)

## ACL bootstrap

If ACLs are enabled, bootstrap after deployment:
```bash
nomad acl bootstrap
```

Save the bootstrap token securely!

## Troubleshooting

### Service won't start
```bash
# Check service status
sudo systemctl status nomad

# View logs
sudo journalctl -u nomad -n 50

# Validate configuration
nomad config validate /etc/nomad.d/nomad.hcl
```

### Cloud auto-join not working
```bash
# Check IAM permissions
aws sts get-caller-identity

# Verify instance tags
aws ec2 describe-instances --instance-ids $(ec2-metadata --instance-id | cut -d' ' -f2)

# Check Nomad logs for auto-join messages
sudo journalctl -u nomad | grep "auto-join"
```

### Clients not connecting
```bash
# Check network connectivity
telnet <server-ip> 4647

# Verify server discovery
nomad agent-info | grep servers
```

## Security considerations

- Runs as root by default (required for Docker access)
- Configuration files have restrictive permissions (0600)
- Consider enabling ACLs for production
- TLS is enabled by default (`nomad_tls_enabled: true`); Nomad's HTTP and RPC layers are TLS-only with no loopback exception
- Restrict network access via security groups

## Upgrade process

To upgrade Nomad:
1. Update `nomad_binary_version` variable
2. Run the playbook
3. Service will restart automatically

## Author

Created for nomad-infra project