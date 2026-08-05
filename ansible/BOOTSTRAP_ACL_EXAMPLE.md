# Nomad ACL bootstrap example

This guide demonstrates how to bootstrap the Nomad ACL system using the `playbooks/nomad_acl_bootstrap.yaml` sub-playbook.

> **Tip:** When you use a use case entrypoint such as `deploy_nomad.yaml` or `deploy_consul_nomad_sd.yaml`, ACL bootstrap runs automatically. Run this playbook directly only when you are deploying Nomad layer-by-layer.

## Prerequisites

1. Nomad cluster deployed and running
2. ACLs enabled in Nomad configuration (`nomad_acl_enabled: true`)
3. Ansible inventory configured at `ansible/inventory.ini`

## Step 1: Enable ACLs in the playbook

ACLs are enabled by default in `playbooks/nomad_servers.yaml` and `playbooks/nomad_clients.yaml`:

```yaml
vars:
  nomad_acl_enabled: true
```

## Step 2: Deploy the cluster with ACLs enabled

```bash
cd ansible
ansible-playbook -i inventory.ini playbooks/nomad_servers.yaml
ansible-playbook -i inventory.ini playbooks/nomad_clients.yaml
```

## Step 3: Bootstrap the ACL system

```bash
ansible-playbook -i inventory.ini playbooks/nomad_acl_bootstrap.yaml
```

### Expected output

```
TASK [Display bootstrap success message] ***************************************
ok: [server-1] => {
    "msg": [
        "==========================================",
        "NOMAD ACL BOOTSTRAP SUCCESSFUL",
        "==========================================",
        "",
        "Secret ID: 12345678-1234-1234-1234-123456789abc",
        "",
        "Token files saved to:",
        "  - ansible/tokens/nomad-bootstrap-token-output.txt (full details)",
        "  - ansible/tokens/nomad-bootstrap-secret-id.txt (token only)",
        "",
        "IMPORTANT: Save these tokens securely!",
        "They provide full administrative access to your Nomad cluster.",
        "",
        "To use the token:",
        "  export NOMAD_TOKEN=12345678-1234-1234-1234-123456789abc",
        "",
        "=========================================="
    ]
}
```

## Step 4: Use the bootstrap token

### Option A: Export as environment variable

```bash
export NOMAD_TOKEN=$(cat ansible/tokens/nomad-bootstrap-secret-id.txt)
nomad status
nomad node status
```

### Option B: Use with individual commands

```bash
nomad status -token=$(cat ansible/tokens/nomad-bootstrap-secret-id.txt)
```

### Option C: Source the cluster environment script

```bash
source ansible/set-cluster-env.sh
```

This sets `NOMAD_ADDR` and `NOMAD_TOKEN` in one step by reading from `ansible/tokens/`.

## Step 5: Create additional ACL tokens

Once bootstrapped, create tokens for different use cases:

### Create a read-only token

```bash
# Create policy file
cat > readonly-policy.hcl <<EOF
namespace "default" {
  policy = "read"
}
EOF

# Create the policy
nomad acl policy apply readonly-policy readonly-policy.hcl

# Create a token with the policy
nomad acl token create -name="readonly-token" -policy=readonly-policy
```

### Create a developer token

```bash
# Create policy file
cat > developer-policy.hcl <<EOF
namespace "default" {
  policy = "write"
}
EOF

# Create the policy
nomad acl policy apply developer-policy developer-policy.hcl

# Create a token with the policy
nomad acl token create -name="developer-token" -policy=developer-policy
```

## Token files

After bootstrap, two files are written to `ansible/tokens/` (mode 0600):

### ansible/tokens/nomad-bootstrap-token-output.txt (full details)

```
Nomad ACL Bootstrap Token
=========================
Generated: 2024-01-15 10:30:00 UTC

Accessor ID  = 12345678-1234-1234-1234-123456789abc
Secret ID    = 12345678-1234-1234-1234-123456789abc
Name         = Bootstrap Token
Type         = management
Global       = true
Create Time  = 2024-01-15 10:30:00 +0000 UTC
Expiry Time  = <none>

Quick Reference
===============
Secret ID: 12345678-1234-1234-1234-123456789abc

Usage
=====
Export the token:
  export NOMAD_TOKEN=12345678-1234-1234-1234-123456789abc

Or use with commands:
  nomad status -token=12345678-1234-1234-1234-123456789abc
```

### ansible/tokens/nomad-bootstrap-secret-id.txt (token only)

```
12345678-1234-1234-1234-123456789abc
```

## Troubleshooting

### ACL system already bootstrapped

If you run the playbook again after a previous successful bootstrap, the playbook detects the already-bootstrapped state and exits cleanly without error.

### Lost bootstrap token

If you lose the bootstrap token and the ACL system is already bootstrapped:

1. **Option 1**: Use an existing management token to create a new one.
2. **Option 2**: Reset the ACL system (requires cluster restart):

```bash
# Stop all Nomad servers
ansible servers -m service -a "name=nomad state=stopped" -b

# Remove ACL state
ansible servers -m file -a "path=/opt/nomad/data/server/raft/raft.db state=absent" -b

# Restart servers
ansible-playbook -i inventory.ini playbooks/nomad_servers.yaml

# Bootstrap again
ansible-playbook -i inventory.ini playbooks/nomad_acl_bootstrap.yaml
```

### ACLs not enabled

If ACLs are not enabled in the Nomad configuration, the bootstrap fails with:

```
fatal: [server-1]: FAILED! => {
    "msg": "Failed to bootstrap Nomad ACL system.\n\nError: ACL support disabled"
}
```

**Solution**: Enable ACLs in your playbook vars and redeploy:

```yaml
vars:
  nomad_acl_enabled: true
```

## Security best practices

1. **Secure token storage**: Keep token files in `ansible/tokens/` (already git-ignored). For production, store tokens in a secrets manager such as HashiCorp Vault or AWS Secrets Manager.
2. **Principle of least privilege**: Do not use the bootstrap token for day-to-day operations. Create specific tokens with limited permissions.
3. **Token expiration**: Consider setting TTLs on tokens and implementing token rotation policies.

4. **Audit Logging**:
   - Enable audit logging in Nomad
   - Monitor token usage
   - Review access patterns regularly

## Next steps

1. Create ACL policies for different roles
2. Generate tokens for applications and users
3. Configure Nomad CLI with appropriate tokens
4. Set up token rotation procedures
5. Implement monitoring and alerting for ACL events

## References

- [Nomad ACL System Documentation](https://developer.hashicorp.com/nomad/docs/configuration/acl)
- [Nomad ACL Policies](https://developer.hashicorp.com/nomad/docs/other-specifications/acl-policy)
- [Nomad ACL Tokens](https://developer.hashicorp.com/nomad/docs/commands/acl/token)