# Helper Role

## Description

The helper role is a utility role that provides common operations for Ansible
playbooks. It simplifies repetitive tasks like package installation, file
operations, directory synchronization, and systemd service management. This role
makes playbooks cleaner and more maintainable by centralizing common patterns.

## Features

- **Package Management**: Install APT or YUM packages
- **File Operations**: Copy files, write content, process templates
- **Directory Sync**: Synchronize local directories to remote hosts
- **Systemd Management**: Start and enable services
- **Debugging**: Print host facts for troubleshooting

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `helper_apt_packages` | list | `[]` | APT packages to install (Debian/Ubuntu) |
| `helper_yum_packages` | list | `[]` | YUM packages to install (RHEL/CentOS) |
| `helper_file_copy_local` | list | `[]` | Files to copy from local to remote |
| `helper_file_write_template` | list | `[]` | Templates to process and write |
| `helper_file_write_content` | list | `[]` | Content to write directly to files |
| `helper_file_write_content_local` | list | `[]` | Content to write to localhost |
| `helper_sync_local_paths` | list | `[]` | Directories to sync from local to remote |
| `helper_systemd_start_service_name` | string | `""` | Service name to start/enable |
| `helper_print_host_facts` | bool | `false` | Print all host facts for debugging |

## Usage

### In Playbooks

This role is used in both server and client playbooks for various utility operations.

**Server Playbook** (`playbooks/nomad_servers.yaml`):
```yaml
- role: helper
  when: nomad_tls_enabled | bool
  vars:
    helper_file_copy_local:
      - src: "{{ inventory_dir }}/.tls/ca.pem"
        dst: "/etc/nomad.d/.tls/ca.crt"
        mode: "0644"
      - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}.pem"
        dst: "/etc/nomad.d/.tls/nomad.crt"
        mode: "0644"
      - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}-key.pem"
        dst: "/etc/nomad.d/.tls/nomad.key"
        mode: "0600"
```

**Client Playbook** (`playbooks/nomad_clients.yaml`):
```yaml
- role: helper
  when: nomad_tls_enabled | bool
  vars:
    helper_file_copy_local:
      - src: "{{ inventory_dir }}/.tls/ca.pem"
        dst: "/etc/nomad.d/.tls/ca.crt"
        mode: "0644"
      - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}.pem"
        dst: "/etc/nomad.d/.tls/nomad.crt"
        mode: "0644"
      - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}-key.pem"
        dst: "/etc/nomad.d/.tls/nomad.key"
        mode: "0600"
```

## Feature Details

### 1. Package management

Install packages based on the system's package manager:

```yaml
- role: helper
  vars:
    helper_apt_packages:
      - curl
      - wget
      - jq
    helper_yum_packages:
      - curl
      - wget
      - jq
```

The role automatically detects the package manager and uses the appropriate list.

### 2. File Copy from Local

Copy files from the Ansible control machine to remote hosts:

```yaml
- role: helper
  vars:
    helper_file_copy_local:
      - src: /local/path/config.yaml
        dst: /etc/app/config.yaml
        owner: root
        group: root
        mode: "0644"
      - src: /local/path/secret.key
        dst: /etc/app/secret.key
        owner: app
        group: app
        mode: "0600"
```

**Parameters**:
- `src`: Source file path on control machine (required)
- `dst`: Destination path on remote host (required)
- `owner`: File owner (default: root)
- `group`: File group (default: root)
- `mode`: File permissions (default: 0644)
- `dir_mode`: Directory permissions (default: 0755)

### 3. Write content to files

Write string content directly to files on remote hosts:

```yaml
- role: helper
  vars:
    helper_file_write_content:
      - content: |
          server {
            listen 80;
            server_name example.com;
          }
        dst: /etc/nginx/sites-available/example
        owner: root
        group: root
        mode: "0644"
```

**Parameters**:
- `content`: Content to write (required)
- `dst`: Destination file path (required)
- `owner`: File owner (default: root)
- `group`: File group (default: root)
- `mode`: File permissions (default: 0644)
- `dir_mode`: Directory permissions (default: 0755)

### 4. Write Templates

Process Jinja2 templates and write to remote hosts:

```yaml
- role: helper
  vars:
    helper_file_write_template:
      - src: templates/app.conf.j2
        dst: /etc/app/app.conf
        owner: app
        group: app
        mode: "0600"
```

**Parameters**:
- `src`: Template file path (required)
- `dst`: Destination file path (required)
- `owner`: File owner (default: root)
- `group`: File group (default: root)
- `mode`: File permissions (default: 0644)
- `dir_mode`: Directory permissions (default: 0755)

### 5. Write content locally

Write content to files on the Ansible control machine:

```yaml
- role: helper
  vars:
    helper_file_write_content_local:
      - content: "{{ nomad_token }}"
        dst: "{{ inventory_dir }}/tokens/nomad_token.txt"
        mode: "0600"
```

This is useful for saving generated tokens, keys, or configuration files locally.

### 6. Sync directories

Synchronize entire directories from local to remote:

```yaml
- role: helper
  vars:
    helper_sync_local_paths:
      - /local/app/dist
      - /local/configs
```

Files are synced to `/home/{{ ansible_user }}/` on remote hosts.

### 7. Systemd service management

Start and enable a systemd service:

```yaml
- role: helper
  vars:
    helper_systemd_start_service_name: "nomad"
```

### 8. Debug host facts

Print all host variables for troubleshooting:

```yaml
- role: helper
  vars:
    helper_print_host_facts: true
```

## Complete example

```yaml
- hosts: servers
  roles:
    - role: helper
      vars:
        # Install packages
        helper_apt_packages:
          - jq
          - curl
          - git
        
        # Copy TLS certificates
        helper_file_copy_local:
          - src: .tls/ca.pem
            dst: /etc/app/.tls/ca.crt
            mode: "0644"
          - src: .tls/server.key
            dst: /etc/app/.tls/server.key
            mode: "0600"
        
        # Write configuration
        helper_file_write_content:
          - content: |
              log_level = "INFO"
              bind_addr = "0.0.0.0"
            dst: /etc/app/config.hcl
            mode: "0644"
        
        # Process template
        helper_file_write_template:
          - src: templates/service.conf.j2
            dst: /etc/app/service.conf
        
        # Save token locally
        helper_file_write_content_local:
          - content: "{{ generated_token }}"
            dst: "{{ inventory_dir }}/tokens/token.txt"
            mode: "0600"
        
        # Start service
        helper_systemd_start_service_name: "myapp"
```

## Dependencies

- `ansible.posix` collection (for synchronize module)

Install with:
```bash
ansible-galaxy collection install ansible.posix
```

## Benefits

1. **DRY Principle**: Avoid repeating common tasks
2. **Consistency**: Standardized way to perform operations
3. **Maintainability**: Centralized location for common patterns
4. **Flexibility**: Can be used with different variables in any playbook
5. **Error Handling**: Built-in directory creation and permission management

## Notes

- File operations automatically create parent directories
- Package installation is conditional based on package manager
- All file operations support custom ownership and permissions
- The role is idempotent - safe to run multiple times
- Synchronize requires rsync on both control and remote hosts

## Troubleshooting

### Packages not installing
```bash
# Check package manager
ansible all -m setup -a "filter=ansible_pkg_mgr"

# Verify package names
apt-cache search <package>  # Debian/Ubuntu
yum search <package>        # RHEL/CentOS
```

### File copy fails
```bash
# Check source file exists
ls -la /local/path/file

# Verify destination directory permissions
ansible all -b -m file -a "path=/etc/app state=directory"
```

### Sync fails
```bash
# Ensure rsync is installed
ansible all -m package -a "name=rsync state=present"

# Check SSH connectivity
ansible all -m ping
```

## Author

Created for nomad-infra project