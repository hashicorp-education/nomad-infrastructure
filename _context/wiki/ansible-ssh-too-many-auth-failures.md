# "Too many authentication failures" running Ansible against fresh AWS hosts (2026-07-21)

After `terraform apply` in `terraform/aws/` created a brand-new cluster,
`ansible all -m ping` failed against every host:

```
[ERROR]: Task failed: Data could not be sent to remote host "52.15.150.167".
Make sure this host can be reached over ssh: Received disconnect from
52.15.150.167 port 22:2: Too many authentication failures
```

The generated `ansible/inventory.ini` and `ssh_key.pem` were both correct —
a direct `ssh -i ssh_key.pem ubuntu@<ip>` with no other flags reproduced the
same disconnect, confirming this wasn't an Ansible-specific bug, just an SSH
one Ansible happened to trigger.

## Root cause

Two things compounding:

1. `~/.ssh/config` (the user's own, outside this repo) has a global `Host *`
   block with `AddKeysToAgent yes` and `UseKeychain yes`. Every time an SSH
   connection succeeded using a **freshly Terraform-generated** `ssh_key.pem`
   (each `terraform apply` in `terraform/aws/` generates a new keypair), that
   key got silently added to the long-lived macOS ssh-agent — and never
   removed. `ssh-add -l` showed **6 stale, differently-fingerprinted keys all
   labeled `ssh_key.pem`** (leftovers from past sessions' clusters, long
   since destroyed) plus the user's real personal key — 7 total.
2. `ansible.cfg`'s `[ssh_connection] ssh_args` did not set
   `IdentitiesOnly=yes`. Without it, every Ansible SSH connection offered
   **all 7 agent keys** before ever trying the one actually specified via
   `private_key_file` / `ansible_ssh_private_key_file` in the inventory.
   AWS's sshd (default `MaxAuthTries=6`) disconnected for too many failed
   attempts before authentication ever reached the correct key — even though
   that key was completely correct and present.

Notably, `terraform/aws/outputs.tf`'s `ssh_commands` output **already**
includes `-o 'IdentitiesOnly yes'` in the manual SSH command it prints for
convenience — the repo's authors clearly knew this was needed for direct SSH
use, it just hadn't been carried over to `ansible.cfg`, so Ansible-driven
connections didn't get the same protection.

## Fix

Added `-o IdentitiesOnly=yes` to `ansible.cfg`'s `ssh_args`:

```ini
[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no -o IdentitiesOnly=yes
```

This restricts auth attempts to the identity file(s) actually configured
(the inventory's `ssh_key.pem`, plus whatever the user's own `~/.ssh/config`
explicitly lists as an `IdentityFile` for all hosts — in this case exactly
one extra, well under `MaxAuthTries`), regardless of how many unrelated keys
have accumulated in the local agent over time. No changes needed to the
agent itself, and no risk of breaking the user's other SSH usage — the fix
is scoped to this repo's `ansible.cfg`, not the user's global SSH config.

**Verified**: manual `ssh -o IdentitiesOnly=yes -i ssh_key.pem ubuntu@<ip>`
connected cleanly; `ansible all -m ping` then succeeded (`pong`) against all
5 freshly-created AWS hosts (3 servers, 2 clients).

## Why this matters going forward

This fix is permanent and general — it protects against the *same class* of
problem recurring for anyone whose local agent accumulates keys over
repeated `terraform destroy`/`apply` cycles (this repo generates a fresh
keypair every AWS apply), not just this one incident. Nobody needs to
remember to manually clean out their ssh-agent before running Ansible again.

## Related

- `terraform/aws/outputs.tf`'s `ssh_commands` output — already had the
  matching `IdentitiesOnly yes` flag for manual SSH; this fix brings
  `ansible.cfg` in line with that existing precedent rather than introducing
  a new pattern.
