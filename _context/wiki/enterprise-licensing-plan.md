# Plan: Nomad/Consul Enterprise licensing (Phase 6)

**Status: implemented and fully verified end-to-end on both Multipass and
AWS.** See "Results" at the end of this page.

## Context

`nomad-tutorials-infrastructure-roadmap.md` marked Phase 6 ("Nomad
Enterprise", 5 tutorials on developer.hashicorp.com) as "scaffolded only;
blocked pending an Enterprise license." That block lifted once valid Consul
and Nomad Enterprise licenses became available. The 5 tutorials split into
two distinct pieces:

1. **Install a HashiCorp Enterprise license** + **Deploy a Nomad Enterprise
   cluster** (+ a reference-architecture reading tutorial, no infra) — the
   infra-provisioning concern this phase implements.
2. **Dynamic Application Sizing** (2 tutorials) via the Nomad Autoscaler — a
   separate binary/service/plugin, deferred to Phase 7 (see the roadmap
   doc) since it's materially bigger scope than a license/edition toggle.

## Decisions made

- **Integration style**: a cross-cutting `nomad_edition`/`consul_edition`
  toggle (`oss`/`enterprise`, default `oss`) layered on the existing shared
  playbooks, not a new dedicated entrypoint — consistent with this repo's
  documented lifecycle decision ("one shared cluster, reconfigured via
  playbooks/vars, not a separate workspace per scenario"). Any existing
  scenario (Get Started, C/D/E/F) can opt in by flipping the toggle.
- **License source**: a new gitignored `ansible/licenses/` directory
  (`nomad.hclic`, `consul.hclic`), mirroring the existing `.tls/`/
  `ansible/tokens/` convention for secrets that live outside git — not a
  hardcoded personal path, since this is a public education repo.
- **Platform**: implemented for both AWS and Multipass.

## Technical facts verified during design

- Enterprise release artifacts on releases.hashicorp.com use `+ent` in the
  **version / zip filename**, e.g. `nomad_1.7.5+ent_linux_amd64.zip` —
  confirmed directly against `https://releases.hashicorp.com/nomad/1.7.5+ent/`.
  The existing `hashicorp_release_zip_url` template
  (`{{ product }}_{{ version }}_linux_{{ arch }}.zip`) needed **zero
  changes** — passing `hashicorp_release_product_version: "2.0.4+ent"`
  produces the correct URL automatically. The `hashicorp_release` role's
  existing idempotency check (`consul_binary_version|string not in
  hashicorp_release_installed_version.stdout`) also works unmodified,
  since `"2.0.4+ent"` is a substring of the `consul version`/`nomad
  version` output for a matching install.
- Per HashiCorp's own "Install a HashiCorp Enterprise license" tutorial:
  license can be loaded via `NOMAD_LICENSE`, `NOMAD_LICENSE_PATH`, or a
  `license_path` in the `server{}` config stanza — **only Nomad servers**
  need a license. Consul Enterprise uses the same mechanism but **all
  Consul agents** (servers and clients) need one, not just servers. This
  repo uses the config-file approach (`license_path`) for both, matching
  how TLS certs and ACL tokens are already handled (files distributed by
  Ansible, not passed as env vars).
- This repo already had an **orphaned, unwired**
  `ansible/roles/nomad/templates/license.hcl.j2` scaffold from the original
  Phase 6 planning pass — never included or rendered by anything.
  `tls.hcl.j2` and `driver_plugin.hcl.j2` in the same directory are
  similarly orphaned (pre-existing, out of scope to fix here). The
  established live pattern in this codebase is to inline every conditional
  block (`{% if %}`) directly into the single `nomad.hcl.j2`/`consul.hcl.j2`
  template, not separate include files — so `license.hcl.j2` was deleted
  and its content inlined into `nomad.hcl.j2`'s existing `server{}` block.

## What shipped

- `ansible/group_vars/all.yaml`: `nomad_edition: "oss"` /
  `consul_edition: "oss"` — the single toggle. Documents the required
  `ansible/licenses/{nomad,consul}.hclic` file locations.
- `ansible/roles/nomad/`: `nomad_edition` in `defaults/main.yaml` and
  `meta/argument_specs.yaml`; `tasks/main.yaml` appends `+ent` to
  `hashicorp_release_product_version` when `nomad_edition == 'enterprise'`;
  `templates/nomad.hcl.j2` renders `license_path =
  "{{ nomad_config_dir }}/.license/license.hclic"` inside `server{}` when
  enabled. `README.md` documents the variable.
- `ansible/roles/consul/`: same shape — `consul_edition`, a new
  `consul_license_dir` default (`/etc/consul.d/license`, following Consul's
  existing non-dotfile subdirectory convention, unlike Nomad's `.tls`/
  `.license`), a directory-creation task mirroring the existing TLS
  directory task, and `license_path` rendered near the top level of
  `consul.hcl` (license applies agent-wide, not just inside `server{}`).
- License distribution reuses the exact pattern already proven for TLS
  certs: a `- role: helper` step (using `helper_file_copy_local`, which
  auto-creates the destination directory) added to
  `ansible/playbooks/nomad_servers.yaml`, `consul_servers.yaml`,
  `consul_clients.yaml`, and `get_started.yaml` — `when: nomad_edition ==
  'enterprise'` / `consul_edition == 'enterprise'`. `nomad_clients.yaml`
  needed no change (Nomad clients don't require a license).
- `.gitignore`: added `ansible/licenses/`.

## Results (2026-07-22, Multipass)

Verified against Option C (`deploy_consul_nomad_sd.yaml`, 3 servers + 2
clients).

**Regression pass** (`nomad_edition`/`consul_edition` left at the `oss`
default): `ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml`
completed with `failed=0` on every host — confirms the toggle has zero
effect on existing CE users when left unset.

**Enterprise pass** (`-e nomad_edition=enterprise -e
consul_edition=enterprise`, license files copied to
`ansible/licenses/{nomad,consul}.hclic`):

- **First attempt** used the license files originally at
  `~/Dev/hc-licenses/`, which turned out to be expired trial/dev licenses
  (Consul terminated 2025-07-08, Nomad terminated 2025-10-30). Both agents
  correctly parsed and rejected the license with a precise error — the
  right failure mode, confirming the plumbing itself was already correct.
- With **fresh license files** copied in: full success.
  - Binary install: `+ent` artifacts fetched and installed correctly with
    no role changes — `consul version` → `Consul v2.0.2+ent`,
    `nomad version` → `Nomad v2.0.4+ent` (confirmed on the remote agents;
    the local Mac CLI used for `NOMAD_ADDR`/`CONSUL_HTTP_ADDR` API calls is
    a separately-installed CE build, which is why `nomad license get`
    works locally as an API call but a local `consul license get` doesn't
    — that subcommand only exists in `+ent` builds. Ran `consul license
    get` directly on the remote server via SSH instead, with
    `CONSUL_HTTP_TOKEN` set to the bootstrap management token.)
  - `nomad license get`: `License Status = valid`, expires 2027-08-21, full
    Enterprise feature set (Namespaces, Sentinel Policies, Multiregion
    Deployments, Dynamic Application Sizing, etc.).
  - `consul license get`: `License is valid`, expires 2027-08-21,
    terminates 2027-08-22, full Enterprise module set (Service Mesh, SSO,
    Audit Logging, Admin Partitions, etc.).
  - `ansible-playbook` end-to-end run: `failed=0` on every host.
  - Idempotency: re-running the same playbook produced no re-download of
    either binary — the existing `hashicorp_release` substring version
    check works correctly with `+ent` in the version string, unchanged.
  - Torn down cleanly afterward: `teardown.yaml` → `failed=0` on every
    host, `terraform destroy` → 7 resources destroyed with no errors.

### Operational gotchas hit during this pass (pre-existing, not new bugs)

- **Multipass daemon wedged**: partway through re-verification, `multipassd`
  stopped responding to its own CLI socket (`cannot connect to the
  multipass socket`) and had to be fully uninstalled and reinstalled via
  Homebrew to recover. Unrelated to this repo's code — a local Multipass
  installation issue.
- **Stale Ansible fact cache across a destroy/recreate cycle**: this
  repo's `ansible.cfg` uses `gathering = smart` with a 1-hour
  `fact_caching_timeout`. When VMs were destroyed and recreated with the
  same hostnames but new DHCP-assigned IPs, Ansible reused the still-fresh
  cached facts (including the stale `default_ipv4.address`), so
  `consul_bind_addr` rendered the *previous* run's IP and Consul failed to
  bind (`cannot assign requested address`). This is the exact gotcha
  already documented in
  [multipass-local-testing-plan.md](multipass-local-testing-plan.md);
  fixed by `rm -rf /tmp/ansible_facts` before re-running. Not specific to
  Enterprise licensing — would affect any playbook re-run after a
  destroy/recreate within the cache TTL.

## Results (2026-07-22, AWS)

Verified against Option C (`deploy_consul_nomad_sd.yaml`, 3 servers + 2
clients + 1 ingress client, `t3.micro`/`t3.medium`), same license files as
the Multipass pass.

- `ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml -e
  nomad_edition=enterprise -e consul_edition=enterprise` completed with
  `failed=0` on every host on the **first attempt** — no fact-cache issue
  here since this was a fresh `terraform apply`, not a destroy/recreate
  cycle onto reused hostnames (see the Multipass gotcha above for why that
  distinction matters).
- Binary install confirmed on the remote agents: `consul version` →
  `Consul v2.0.2+ent`, `nomad version` → `Nomad v2.0.4+ent`.
- `nomad license get`: `License Status = valid`, expires 2027-08-21, full
  Enterprise feature set.
- `consul license get` (via SSH with `CONSUL_HTTP_TOKEN` set to the
  bootstrap management token read from `ansible/tokens/consul-bootstrap-secret-id.txt`
  on the control machine — the token lives there, not on the remote host):
  `License is valid`, expires 2027-08-21, terminates 2027-08-22, full
  Enterprise module set.
- Torn down cleanly: `teardown.yaml` → `failed=0` on every host,
  `terraform destroy` → 22 resources destroyed, `terraform state list`
  confirmed empty. No AWS resources left running.

Both platforms now show matching results: `+ent` binaries install
correctly with no changes to `hashicorp_release`, license files distribute
and load correctly via the same `helper` role pattern already used for TLS
certs, and both `nomad license get`/`consul license get` confirm a valid,
current Enterprise license.
