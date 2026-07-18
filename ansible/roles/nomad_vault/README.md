# Nomad-Vault Integration Role

## Description

The `nomad_vault` role configures Vault so that Nomad tasks can authenticate
using their [Nomad workload identity](https://developer.hashicorp.com/nomad/docs/concepts/workload-identity)
JWT instead of a static Vault token. It enables a Vault JWT auth method that
trusts Nomad's JWKS endpoint, creates a Vault ACL policy and JWT role scoped
to Nomad task claims, and enables a KV v2 secrets mount for Nomad workloads
to read from.

This role only touches Vault. It does not modify Nomad's configuration —
after running it, re-run the `nomad` role on servers and clients with
`nomad_vault_integration_enabled: true` and `nomad_vault_workload_identity_enabled: true`
so Nomad renders the matching `vault { jwt_auth_backend_path; default_identity }`
block. See [ansible/playbooks/nomad_vault_integration.yaml](../../playbooks/nomad_vault_integration.yaml).

## Prerequisites

- [ansible/playbooks/vault_servers.yaml](../../playbooks/vault_servers.yaml)
  must have already initialized and unsealed Vault, and saved the root token
  to `ansible/tokens/vault-root-token-secret-id.txt`.
- Nomad must already be running (servers reachable at their JWKS endpoint).

## Features

- Enables a Vault JWT auth method (default path `jwt-nomad`) configured with
  `jwks_url` pointing at the first Nomad server's
  `/.well-known/jwks.json` endpoint
- Creates a read-only Vault ACL policy scoped to `secret/data/nomad/*` and
  `secret/metadata/nomad/*`
- Creates a Vault JWT role mapping Nomad workload identity claims
  (`nomad_namespace`, `nomad_job_id`, `nomad_task`) to that policy
- Enables a KV v2 secrets engine at `secret/` for Nomad workloads (idempotent
  — tolerates "path is already in use")
- Idempotent overall via a sentinel file
  (`/opt/vault/data/nomad-vault-wi-bootstrapped.true`) on the first server

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `nomad_vault_addr` | string | `https://127.0.0.1:8200` | Address of the Vault instance reachable from the first Nomad server |
| `nomad_vault_bin_path` | string | `/usr/local/bin/vault` | Path to the Vault binary on the remote server |
| `nomad_vault_cacert` | string | `/etc/vault.d/.tls/ca.crt` | CA certificate used to validate the local Vault TLS listener |
| `nomad_vault_root_token_file` | string | `{{ inventory_dir }}/tokens/vault-root-token-secret-id.txt` | Local path to the Vault root token written by `vault_servers.yaml` |
| `nomad_vault_wi_bootstrapped_file` | string | `/opt/vault/data/nomad-vault-wi-bootstrapped.true` | Sentinel file marking bootstrap complete |
| `nomad_vault_staging_dir` | string | `/tmp/nomad-vault-acl` | Remote directory used to stage policy/auth-method files (removed after use) |
| `nomad_vault_auth_method_path` | string | `jwt-nomad` | Path at which the Vault JWT auth method is enabled |
| `nomad_vault_jwks_url` | string | *(required)* | JWKS URL Vault uses to validate Nomad workload identity JWTs |
| `nomad_vault_jwks_ca_cert` | string | `""` | PEM CA certificate content used to validate the JWKS endpoint's TLS certificate |
| `nomad_vault_policy_name` | string | `nomad-workloads-policy` | Vault ACL policy name |
| `nomad_vault_role_name` | string | `nomad-workloads` | Vault JWT role name |
| `nomad_vault_role_bound_audiences` | string | `vault.io` | Audience the Vault JWT role accepts; must match `nomad_vault_default_identity_aud` in the `nomad` role |
| `nomad_vault_role_ttl` | string | `1h` | Token TTL issued by the Vault JWT role |
| `nomad_vault_secrets_mount` | string | `secret` | Path of the KV v2 secrets engine enabled for Nomad workloads |

## Example usage

```yaml
- role: nomad_vault
  vars:
    nomad_vault_jwks_url: "https://10.0.1.10:4646/.well-known/jwks.json"
    nomad_vault_jwks_ca_cert: "{{ lookup('file', inventory_dir + '/.tls/ca.pem') }}"
```

See [ansible/playbooks/nomad_vault_integration.yaml](../../playbooks/nomad_vault_integration.yaml)
for the full integration flow.
