---
description: "Use when creating or editing sub-playbooks in ansible/playbooks/. Covers idempotency sentinels, token file patterns, multi-play integration structure, inventory_dir usage, and cluster_summary integration."
name: "Ansible Playbooks Conventions"
applyTo: "ansible/playbooks/**"
---
# Sub-Playbook Conventions — `ansible/playbooks/`

## File Paths — `inventory_dir` vs `playbook_dir`

`inventory_dir` is a per-host magic variable. It is defined for hosts in the inventory (e.g., `servers`, `clients`) but **undefined** for `localhost` plays, because `localhost` is not in `inventory.ini`.

**Rule for plays targeting inventory hosts** (`hosts: servers`, `hosts: clients`): use `inventory_dir`:

```yaml
path: "{{ inventory_dir }}/tokens/consul-bootstrap-secret-id.txt"
path: "{{ inventory_dir }}/.tls/"
```

**Rule for plays targeting `localhost`** (e.g., `cluster_summary.yaml`): borrow `inventory_dir` from the first inventory host via `hostvars`. This returns the absolute path regardless of how the playbook is invoked:

```yaml
lookup('file', hostvars[groups['servers'][0]]['inventory_dir'] + '/tokens/consul-bootstrap-secret-id.txt')
```

Do **not** use `playbook_dir` for token paths in `localhost` plays. When `cluster_summary.yaml` is imported via `import_playbook`, `playbook_dir` resolves to `ansible/playbooks/` (the imported file's directory), so `playbook_dir + '/tokens/'` looks in `ansible/playbooks/tokens/` which does not exist.

## Required Play Boilerplate

Every play must explicitly declare `gather_facts`:

```yaml
- name: Some play
  hosts: servers[0]
  gather_facts: false   # or true — never omit
```

## Idempotency Sentinel Pattern (Bootstrap Plays)

Bootstrap plays (`consul_acl_bootstrap.yaml`, `nomad_acl_bootstrap.yaml`) must run cleanly on re-runs without failing. Use:

```yaml
- name: Attempt to bootstrap
  ansible.builtin.command: "{{ bin_path }} acl bootstrap"
  register: result
  failed_when: false          # do not fail on "already bootstrapped" exit code
  changed_when: result.rc == 0
  no_log: true

- name: Handle bootstrap result
  when: result.rc == 0        # success path only
  block:
    - name: Parse and save token
      ...

- name: Handle already-bootstrapped
  when: result.rc != 0
  block:
    - name: Display saved token
      ...
```

Refer to [consul_acl_bootstrap.yaml](consul_acl_bootstrap.yaml) for the full reference implementation.

## Token Write Pattern

Token files are written on the Ansible control machine with strict permissions.

```yaml
- name: Ensure local tokens directory exists
  ansible.builtin.file:
    path: "{{ inventory_dir }}/tokens"
    state: directory
    mode: "0700"
  delegate_to: localhost
  become: false

- name: Save SecretID to file
  ansible.builtin.copy:
    content: "{{ secret_id }}"
    dest: "{{ inventory_dir }}/tokens/consul-bootstrap-secret-id.txt"
    mode: "0600"
  delegate_to: localhost
  become: false
  no_log: true
```

**Rules:**
- Always `delegate_to: localhost` and `become: false` for local file writes.
- `mode: "0600"` for all token files; `mode: "0700"` for the `tokens/` directory.
- `no_log: true` on every task that handles raw token output or secret content.

## Token Read Pattern (Pre-tasks in Integration Plays)

When a play needs a token from a prior bootstrap step, read it in `pre_tasks`:

```yaml
pre_tasks:
- name: Read Consul server token
  ansible.builtin.command: >-
    cat {{ inventory_dir }}/tokens/nomad-consul-server-secret-id.txt
  changed_when: false
  delegate_to: localhost
  run_once: true
  register: token_file

- name: Set token fact
  ansible.builtin.set_fact:
    nomad_consul_agent_token: "{{ token_file.stdout | trim }}"
```

Note `run_once: true` — read the file once and broadcast the fact; do not read per-host.

## Token Parsing — Regex Patterns

Consul and Nomad use **different** output formats:

| Binary | Field label | Regex |
|--------|-------------|-------|
| `consul acl bootstrap` | `SecretID:` | `regex_search('SecretID:\s+([a-f0-9-]+)', '\1') \| first` |
| `nomad acl bootstrap` | `Secret ID  =` | `regex_search('Secret ID\\s+=\\s+([a-f0-9-]+)', '\\1') \| first` |

## Multi-Play Integration Structure

Plays in `consul_nomad_service_discovery.yaml` and `consul_nomad_workload_identity.yaml` follow a pattern of: create ACL entities first, then re-run the `nomad` role to write the updated config.

```
Play 1 — hosts: servers       — run nomad_consul role (creates policies/tokens/bindings)
Play 2 — hosts: servers       — pre_tasks: read token; vars: role vars; roles: [nomad]
Play 3 — hosts: clients       — pre_tasks: read token; vars: role vars; roles: [nomad]
```

When re-running the `nomad` role in a play, **all** required role variables must be listed explicitly in `vars:` — do not rely on defaults being picked up from a prior play in the same run.

## `nomad_consul` Role Flags

The `nomad_consul` role is gated by two boolean flags. Set exactly one to `true` per playbook:

| Flag | Playbook |
|------|----------|
| `nomad_consul_run_service_discovery: true` | `consul_nomad_service_discovery.yaml` |
| `nomad_consul_run_workload_identity: true` | `consul_nomad_workload_identity.yaml` |

## `cluster_summary.yaml` Integration

Always import `cluster_summary.yaml` at the end of a deploy entrypoint, not in sub-playbooks. Pass variables via `import_playbook vars:` — all variables default to `false` so the playbook is safe to run standalone.

```yaml
- name: Import cluster summary
  ansible.builtin.import_playbook: cluster_summary.yaml
  vars:
    summary_title: "My Cluster Complete!"
    summary_show_consul_tokens: true
    summary_show_consul_env: true
    summary_show_consul_ui: true
```

Refer to the full variable list in the header comment of [cluster_summary.yaml](cluster_summary.yaml).

## Prerequisite Comments

Every sub-playbook with dependencies must document them in a numbered comment at the top:

```yaml
# Prerequisites (all must be complete before running this playbook):
#   1. consul_servers.yaml        — Consul server agents healthy
#   2. consul_acl_bootstrap.yaml  — Consul ACL bootstrapped
```

## Sensitive Files

`ansible/tokens/` is git-ignored. Never add token file names or paths to output that might be logged. Use `no_log: true` on tasks that read, write, or transmit token values.
