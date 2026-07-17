# TLS Role

## Description

The TLS role generates TLS certificates for secure communication in the Nomad cluster. It creates a Certificate Authority (CA) and signs individual certificates for each server and client node. All certificate operations are performed on the Ansible control machine (localhost).

## Features

- Generates self-signed Certificate Authority (CA)
- Creates individual certificates for each node with a non-empty Common Name plus standard `keyUsage`/`extendedKeyUsage` extensions, for RFC 5280-compliant, browser-compatible TLS server certificates
- Signs certificates with the CA
- Supports Subject Alternative Names (SANs) for IP and DNS
- Stores certificates locally for distribution
- Idempotent — the CA is only generated once; node certificates are re-signed automatically (via `community.crypto.x509_certificate_pipe`, `provider: ownca`) whenever the rendered CSR differs from the existing certificate, e.g. after a CSR field change in this role

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `tls_path` | string | `{{ inventory_dir }}/.tls` | Directory to store certificates |
| `tls_ca_generate` | bool | `true` | Generate CA certificate |
| `tls_ca_pem_filename` | string | `ca.pem` | CA certificate filename |
| `tls_ca_key_filename` | string | `ca-key.pem` | CA private key filename |
| `tls_self_signed_generate` | list | `[]` | List of certificates to generate |

### Certificate generation list format

Each item in `tls_self_signed_generate` should contain:
```yaml
- agent-name: "hostname"      # Certificate name
  ip: "192.168.1.10"          # IP address for SAN
  dns: "server.example.com"   # DNS name for SAN
```

## Generated files

The role creates the following files in `{{ tls_path }}` (default: `ansible/.tls/`):

```
ansible/.tls/
├── ca.pem                           # CA certificate (public)
├── ca-key.pem                       # CA private key (sensitive)
├── <agent-name>.pem                 # Node certificate (public)
└── <agent-name>-key.pem             # Node private key (sensitive)
```

## Usage

This role is used in the role list of both server and client playbooks to generate certificates before other roles run. The `when: nomad_tls_enabled` (or `consul_tls_enabled`) condition ensures the role is skipped when TLS is disabled. TLS is enabled by default for both products.

**Nomad server playbook** (`playbooks/nomad_servers.yaml`):
```yaml
- role: tls
  when: nomad_tls_enabled
  tls_self_signed_generate:
  - agent-name: "{{ inventory_hostname }}"
    ip: "{{ ansible_facts['default_ipv4']['address'] }}"
    dns: "server.global.nomad"
```

**Nomad cert distribution** (separate `helper` role call, also in `nomad_servers.yaml`):
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

**Consul server playbook** (`playbooks/consul_servers.yaml`) — same CA, distinct DNS SAN and destination owned by the `consul` user:
```yaml
- role: tls
  when: consul_tls_enabled
  tls_self_signed_generate:
  - agent-name: "{{ inventory_hostname }}"
    ip: "{{ ansible_facts['default_ipv4']['address'] }}"
    dns: "server.{{ consul_datacenter }}.{{ consul_domain }}"

- role: helper
  when: consul_tls_enabled | bool
  vars:
    helper_file_copy_local:
    - src: "{{ inventory_dir }}/.tls/ca.pem"
      dst: "{{ consul_tls_dir }}/ca.pem"
      owner: "{{ consul_user }}"
      group: "{{ consul_group }}"
      mode: "0644"
    - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}.pem"
      dst: "{{ consul_tls_dir }}/consul.pem"
      owner: "{{ consul_user }}"
      group: "{{ consul_group }}"
      mode: "0644"
    - src: "{{ inventory_dir }}/.tls/{{ inventory_hostname }}-key.pem"
      dst: "{{ consul_tls_dir }}/consul-key.pem"
      owner: "{{ consul_user }}"
      group: "{{ consul_group }}"
      mode: "0600"
```

## Certificate details

### CA certificate
- **Common Name**: "Nomad CA"
- **Key Usage**: Certificate Signing
- **Basic Constraints**: CA:TRUE
- **Validity**: Self-signed

### Node certificates
- **Common Name**: the item's `dns` value (e.g. `server.global.nomad`). This keeps the Subject non-empty, which is required by [RFC 5280 §4.2.1.6](https://www.rfc-editor.org/rfc/rfc5280#section-4.2.1.6) whenever the SAN extension is not marked critical — Chrome, Brave, and Safari enforce this strictly and will hard-fail the TLS handshake on a certificate with an empty Subject and a non-critical SAN.
- **Subject Alternative Names** (not marked critical, since Common Name is set):
  - IP: 127.0.0.1 (localhost)
  - IP: Node's IP address
  - IP: Ansible host IP
  - DNS: localhost
  - DNS: Node's DNS name
- **Key Usage** (critical): Digital Signature, Key Encipherment
- **Extended Key Usage**: TLS Web Server Authentication (`serverAuth`) and TLS Web Client Authentication (`clientAuth`) — both purposes are required because Consul (`internal_rpc`) and Nomad (RPC layer) use mutual TLS between servers: each server presents this same node certificate as a TLS *client* cert when connecting to peer servers, not just as a server cert for API/UI traffic. A `serverAuth`-only certificate is rejected during that client-auth handshake, which breaks Raft/gossip and prevents leader election entirely.
- **Signed By**: CA certificate
- **Validity**: 365 days from creation

## Certificate distribution

After generation, certificates are distributed by the **helper** role (see `playbooks/nomad_servers.yaml`, `playbooks/nomad_clients.yaml`, `playbooks/consul_servers.yaml`, and `playbooks/consul_clients.yaml`).

Certificates are written to `/etc/nomad.d/.tls/` (owned by the `nomad` user) and `{{ consul_tls_dir }}` (default `/etc/consul.d/tls/`, owned by the `consul` user) on each node. Consul and Nomad certificates on the same node share the same CA, generated once per cluster.

## Dependencies

- `community.crypto` Ansible collection (for certificate generation)

Install with:
```bash
ansible-galaxy collection install community.crypto
```

## Example configurations

### Generate certificates for multiple nodes

```yaml
- name: Generate TLS certificates
  ansible.builtin.include_role:
    name: tls
  vars:
    tls_self_signed_generate:
      - agent-name: "server-1"
        ip: "10.0.1.10"
        dns: "server-1.example.com"
      - agent-name: "server-2"
        ip: "10.0.1.11"
        dns: "server-2.example.com"
      - agent-name: "client-1"
        ip: "10.0.1.20"
        dns: "client-1.example.com"
  run_once: true
  delegate_to: localhost
```

### Custom certificate path

```yaml
- name: Generate TLS certificates
  ansible.builtin.include_role:
    name: tls
  vars:
    tls_path: "/tmp/nomad-certs"
    tls_self_signed_generate:
      - agent-name: "{{ inventory_hostname }}"
        ip: "{{ ansible_default_ipv4.address }}"
        dns: "{{ inventory_hostname }}"
```

## Security considerations

### File permissions
- CA private key: Stored locally, should be protected
- Node private keys: Should have 0600 permissions when copied to nodes
- Certificates (public): Can have 0644 permissions

### Certificate validity
- Certificates are valid for 365 days
- Plan for certificate rotation before expiry
- Consider implementing automated renewal

### CA protection
- The CA private key (`ca-key.pem`) can sign new certificates
- Keep it secure and backed up
- Consider using a proper PKI for production

## Certificate rotation

To rotate certificates:

1. **Delete existing certificates**:
```bash
rm -rf ansible/.tls/
```

2. **Re-run playbooks**:
```bash
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml
```

3. **Restart Nomad services**:
```bash
ansible all -b -m systemd -a "name=nomad state=restarted"
```

## Troubleshooting

### Certificates not generated
```bash
# Check if community.crypto is installed
ansible-galaxy collection list | grep community.crypto

# Verify TLS directory exists
ls -la ansible/.tls/

# Check for errors in playbook output
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml -vvv
```

### Certificate validation errors
```bash
# Verify certificate
openssl x509 -in ansible/.tls/server-1.pem -text -noout

# Check CA certificate
openssl x509 -in ansible/.tls/ca.pem -text -noout

# Verify certificate chain
openssl verify -CAfile ansible/.tls/ca.pem ansible/.tls/server-1.pem
```

### SAN issues
```bash
# Check Subject Alternative Names
openssl x509 -in ansible/.tls/server-1.pem -text -noout | grep -A1 "Subject Alternative Name"
```

## Integration with Nomad

After certificates are generated and distributed, configure Nomad to use them:

```hcl
tls {
  http = true
  rpc  = true

  ca_file   = "/etc/nomad.d/.tls/ca.crt"
  cert_file = "/etc/nomad.d/.tls/nomad.crt"
  key_file  = "/etc/nomad.d/.tls/nomad.key"

  verify_server_hostname = true
  verify_https_client    = true
}
```

## Notes

- All certificate operations run on localhost (Ansible control machine)
- Certificates are generated once per playbook run (`run_once: true`)
- The role is idempotent - existing certificates are not regenerated
- For production, consider using a proper Certificate Authority
- Certificate expiry monitoring should be implemented

## Author

Created for nomad-infra project