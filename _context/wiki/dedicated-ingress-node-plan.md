# Plan: Dedicated public "ingress" Nomad client for the API Gateway

**Status: implemented and verified end-to-end on the live AWS cluster.**
Approved by the user 2026-07-21; implemented and verified 2026-07-22. See
"Results (2026-07-22)" at the end of this page for what shipped, one real
pre-existing bug found and fixed along the way, and the live verification
evidence.

## Context

Today all Nomad clients are identical and fully public: one shared security
group (`aws_security_group.nomad_consul_sg` in `terraform/aws/network.tf`)
opens every app port — including the API Gateway's `8447` — to `0.0.0.0/0`
on **every** client, and the API Gateway job (the front door for Countdash's
default transparent-proxy mesh job, see
[transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md);
`nomad-jobs/consul-mesh/api-gateway.nomad.hcl`) can be scheduled onto either
client, unpredictably. This showed up concretely in the same session that
produced this plan: finding the gateway's public URL required a multi-step
lookup (`nomad alloc status` → node name → `terraform output`) specifically
because the gateway could land anywhere — see the "Viewing the app in your
web browser" section added to
[`nomad-jobs/consul-mesh/README.md`](../../nomad-jobs/consul-mesh/README.md)
that session.

The goal: designate one client as the public-facing "ingress" node. Only
that node's security group opens app-facing ports; the API Gateway job is
constrained to always schedule there. The other clients keep public IPs
(see the isolation-depth decision below) but don't get app ports opened,
and internal-mesh services never need to be reachable directly.

**Precedent already proven in a sibling repo**
(`learn-consul-nomad-vm/aws/`), confirmed by reading its Terraform and job
specs directly: it provisions a NAT Gateway + private subnets via the
`terraform-aws-modules/vpc` module but never actually places any instance
in the private subnets — every instance, including its "ingress" client,
lives in the public subnet with a public IP. Its actual public/private
split is achieved by (a) a dedicated security group attached only to the
ingress instance, and (b) Nomad client `meta { nodeRole = "ingress" }`
(injected per-instance via Terraform templatefile/user-data) combined with
a job-level `constraint { attribute = "${meta.nodeRole}" ... value =
"ingress" }` in its `api-gateway.nomad.hcl`. This plan adapts that same
mechanism to this repo's Ansible-based (not user-data-based) provisioning.

**Decisions already made with the user:**
- **No NAT Gateway / true private subnet** — all clients keep public IPs,
  only the ingress client's security group differs. Cheaper, matches this
  repo's existing single-flat-SG convention, matches the sibling repo's
  actual (not just provisioned) behavior. The alternative considered (a
  real private subnet + NAT Gateway, giving true network-level isolation)
  was rejected primarily on cost/complexity grounds — this repo's clients
  need outbound internet access for `docker pull` and HashiCorp release
  downloads during provisioning, so true private clients would need the
  NAT Gateway regardless.
- **Scope is Option E (service mesh) only** — just
  `nomad-jobs/consul-mesh/api-gateway.nomad.hcl` gets the ingress
  constraint. The non-mesh Countdash/HashiCups job specs in `consul-sd/`
  and `nomad-sd/` (which expose ports directly, no gateway involved) are
  untouched.

**Side benefit**: once the gateway always lands on the same node, the
"Viewing the app in your web browser" section in
`nomad-jobs/consul-mesh/README.md` can drop its `nomad alloc status` →
`Node Name` lookup step — the ingress node's address is fixed and known
from `terraform output` alone.

## Implementation plan

### 1. Terraform — new ingress client + dedicated security group

`terraform/aws/network.tf`:
- New `aws_security_group "ingress_sg"` — opens `8447` (API Gateway HTTPS)
  to `0.0.0.0/0`. Separate resource, not added to the existing
  `extra_ingress_ports` dynamic block on `nomad_consul_sg` (which stays as
  today, for ports non-mesh scenarios still need on every client, e.g.
  Countdash's `9002` / HashiCups' `443` — those scenarios are out of scope
  here).

`terraform/aws/variables.tf`:
- New `variable "ingress_client_count"` (default `1`) — mirrors
  `client_count`'s shape, kept separate rather than overloading
  `client_count`, so `terraform.tfvars` reads clearly (`client_count = 2`,
  `ingress_client_count = 1`) and matches the sibling repo's
  `public_client_count` pattern.

`terraform/aws/compute.tf`:
- New `aws_instance "ingress_clients"` resource — copy of
  `aws_instance.clients` (same AMI/instance type/subnet/IMDSv2 hardening),
  `count = var.ingress_client_count`, `vpc_security_group_ids = [
  aws_security_group.nomad_consul_sg.id, aws_security_group.ingress_sg.id
  ]`, tags `Name = "${var.project_name}-ingress-client-${count.index + 1}"`,
  same `AutoJoinRole = "client"` (so Consul/Nomad server `retry_join`
  discovery is unaffected — it already matches on this tag, not on
  instance identity).
- `local_file.ansible_inventory`'s `templatefile()` call: merge
  `aws_instance.clients` and `aws_instance.ingress_clients` into a single
  `clients` map keyed by tag name, each entry additionally carrying
  `role = "internal"` or `role = "ingress"`.

`terraform/aws/inventory.tpl`:
- `[clients]` loop emits an extra inline var per host:
  `nomad_node_role=${instance.role}`. Both node types stay in the **same**
  `[clients]` Ansible group — every existing playbook that targets `hosts:
  clients` (base bring-up, mesh enablement) automatically covers the new
  node with zero playbook changes; only the per-host var differs.

`terraform/aws/terraform.tfvars`:
- Add `ingress_client_count = 1`.
- Remove the `{ port = 8447, description = "Consul API Gateway - HTTPS
  ingress" }` entry from `extra_ingress_ports` — 8447 is now opened
  unconditionally by the new dedicated SG, so this manual step goes away
  entirely (a real simplification to the current deploy docs, not just a
  refactor).

### 2. Ansible — node metadata sourced from the inventory var, not a play `vars:`

This repo has hit the "a var must be re-supplied in every play that
re-renders the same config file" bug class twice already (the Consul DNS
ACL token regression and the `nomad_client_use_consul_token` gotcha
documented in `acl-architecture.md` §10 — see also
[transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md)'s
Bug 2). To avoid a third instance of it here, `nodeRole` is **not** set as
a literal in any play's `vars:` — it's a role default computed directly
from the per-host inventory fact, so every playbook that renders
`nomad.hcl` picks it up automatically, forever, with nothing to remember to
re-supply.

`ansible/roles/nomad/defaults/main.yaml`:
- New default:
  ```yaml
  # Nomad client meta stanza. Sourced from the per-host `nomad_node_role`
  # inventory var (set by terraform/aws/inventory.tpl) rather than passed
  # explicitly by any play, so every play that renders nomad.hcl picks it
  # up automatically — see the ansible/roles/nomad/README.md note on why
  # (this repo has hit the "forgot to re-supply a var on re-render" bug
  # class before).
  nomad_client_meta: "{{ {'nodeRole': nomad_node_role} if nomad_node_role is defined else {} }}"
  ```

`ansible/roles/nomad/templates/nomad.hcl.j2`:
- Inside the existing `client { ... }` block (after the `template
  { use_client_consul_token = true }` conditional, before its closing
  `}`), add:
  ```jinja
  {% if nomad_client_meta %}

    meta {
  {% for k, v in nomad_client_meta.items() %}
      {{ k }} = "{{ v }}"
  {% endfor %}
    }
  {% endif %}
  ```

No changes needed to `nomad_clients.yaml`'s `vars:` or
`consul_nomad_service_mesh.yaml` Play 2/3's `vars:` — `nomad_client_meta`
resolves from `hostvars[inventory_hostname].nomad_node_role`
automatically wherever the `nomad` role runs.

`nomad_clients.yaml`'s existing `nomad_node_name:
"nomad-client-{{ groups['clients'].index(inventory_hostname) + 1 }}"`
is left unchanged — the new ingress client gets folded into the same
sequential numbering (e.g. `nomad-client-3`) rather than a distinct name
like `nomad-ingress-client-1`. The constraint mechanism only depends on
`meta.nodeRole`, not the node name, so this is cosmetic only; not worth
the added Jinja complexity/risk for a one-off name. (Flagged explicitly in
case a prettier name is wanted later — easy to add.)

### 3. Nomad job spec — pin the gateway

`nomad-jobs/consul-mesh/api-gateway.nomad.hcl`, `group "gateway"` block
(currently `count = 1`, `shutdown_delay = "10s"`, then `network {...}`):
add, immediately after `shutdown_delay`:
```hcl
constraint {
  attribute = "${meta.nodeRole}"
  operator  = "="
  value     = "ingress"
}
```
Matches the sibling repo's proven syntax exactly.

### 4. Docs

- `nomad-jobs/consul-mesh/README.md`:
  - Prerequisites: remove the manual "Port 8447 must be open... `terraform
    apply`" step — no longer needed, the new SG handles it unconditionally.
  - Simplify the "Viewing the app in your web browser" section: since the
    gateway always lands on the ingress node now, Step A (`nomad alloc
    status` → `Node Name`) can be dropped; go straight from `terraform
    output client_public_ips_by_node` (look for the `*-ingress-client-1`
    entry) to opening the browser.
  - File index / architecture note mentioning the dedicated ingress client.
- `DEPLOY_CLUSTER_GUIDE.md`: update the `client_count` variable-table row
  area to also mention `ingress_client_count`, and the Option E section to
  note the API Gateway now always runs on a dedicated ingress client.
- Note (not a file change): `terraform/aws/loadbalancer.tf`'s optional ALB
  (`enable_load_balancer`) target-group attachment only loops over
  `aws_instance.clients`, not the new `ingress_clients` — that's an
  unrelated, separate optional feature and is out of scope here, but
  worth knowing it won't auto-include the ingress node if that ALB is
  ever turned on for Option E.

## Verification (live AWS cluster, when implemented)

1. `terraform plan` in `terraform/aws/` — confirm it's additive only (new
   SG, new instance, updated inventory file) with **no** destroy/replace of
   the existing 2 clients or servers.
2. `terraform apply`; confirm `terraform output client_public_ips_by_node`
   now lists 3 client entries including `nomad-ingress-client-1`, and that
   `ansible/inventory.ini`'s `[clients]` block shows `nomad_node_role=ingress`
   on exactly one line, `nomad_node_role=internal` on the other two.
3. Re-run the full bring-up chain (`deploy_consul_nomad_wi.yaml` then
   `consul_nomad_service_mesh.yaml`) — idempotent re-run against existing
   nodes, full first-time provisioning against the new one.
4. `nomad node status -verbose <ingress-node-id> | grep -i noderole` (or
   equivalent) confirms `meta.nodeRole = ingress` only on the new node.
5. Stop/purge and redeploy `api-gateway.nomad.hcl`; confirm via `nomad job
   status -namespace ingress api-gateway` that it always places on the
   ingress node (repeat 2-3 times to be sure it's not coincidental).
6. Confirm the security-group split: from a machine outside the VPC,
   `curl -k https://<internal-client-ip>:8447/` should time out/refuse
   (port not open there), while `curl -k
   https://<ingress-client-ip>:8447/` succeeds.
7. Full functional check: Countdash traffic through the gateway still
   returns `HTTP 200`, same as the prior session's verification (see
   [transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md)).
8. Update this page's status to "implemented and verified" once done,
   following this repo's established pattern of recording what shipped.

## Related

- [transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md) —
  the API Gateway and transparent-proxy mesh this plan builds the ingress
  node for.
- [acl-architecture.md §10](acl-architecture.md#10-common-acl-failure-modes) —
  the "must re-supply a var on every re-render" bug class this plan's
  Ansible design (§2 above) is deliberately built to avoid.
- `learn-consul-nomad-vm/aws/` (sibling repo) — source of the
  `meta.nodeRole` + `constraint` pattern this plan adapts; see
  `aws-ec2-data_plane.tf`, `agent-config-nomad_client.hcl`, and
  `shared/jobs/04.api-gateway.nomad.hcl` there.

## Results (2026-07-22)

Implemented exactly as planned in §1–4, with two adjustments discovered
only once implementation started — both against the live 3-server/3-client
AWS cluster (Consul v2.0.2, Nomad v2.0.4):

**Adjustment 1 — a real bug in `consul_nomad_api_gateway.yaml` that would
have quietly defeated the whole plan.** That "shortcut" playbook imported
`update-security-group.yaml` with `custom_port: 8447`, which opens 8447 on
the **shared** `nomad_consul_sg` group used by every client — i.e. running
the shortcut playbook would have re-opened 8447 on the internal clients
too, on top of the new dedicated `ingress_sg`. It also generated the
gateway's self-signed cert with every client's IP in the SAN list, and
probed every client's `:8447` for reachability post-deploy. Fixed by: (1)
removing the SG-open import entirely — 8447 is now opened unconditionally
by Terraform's `ingress_sg`, so the playbook doesn't need to touch security
groups at all; (2) adding an `ingress_clients` fact (`groups['clients'] |
map('extract', hostvars) | selectattr('nomad_node_role', 'equalto',
'ingress') | map(attribute='inventory_hostname') | list`) and using it for
both the cert's SAN list and the post-deploy reachability probe, instead of
`groups['clients']`.

**Adjustment 2 — a pre-existing idempotency bug in `consul_dns_token.yaml`,
unrelated to this plan but blocking it.** Its per-client Consul node-identity
agent token creation used a single "sentinel" file
(`consul-client-agent-{{ groups['clients'][0] }}-secret-id.txt`) to decide
whether *any* client needed a token created. Since the two original clients
already had tokens, adding the third (ingress) client via `terraform apply`
caused the sentinel check to report "already done" and skip token creation
entirely — the new node never got a token, and `deploy_consul_nomad_wi.yaml`
failed with `fatal: [nomad-consul-ingress-client-1 -> localhost]` reading a
token file that didn't exist. Fixed by replacing the single sentinel with a
per-client `stat` loop + `rejectattr('stat.exists')` to compute exactly
which clients are missing a token, and looping token creation over only
those. This is a general fix (any future client added to an
already-bootstrapped cluster benefits), not ingress-node-specific, but it
was surfaced by and blocking this plan's live verification.

**Verification — all steps from the Verification section above passed:**

1. `terraform plan` was additive-only: `aws_instance.ingress_clients[0]`
   and `aws_security_group.ingress_sg` created, `aws_security_group
   .nomad_consul_sg` updated in-place (8447 rule removed) — zero
   destroy/replace of the existing 3 servers or 2 clients.
2. Post-apply, `ansible/inventory.ini`'s `[clients]` block showed
   `nomad_node_role=internal` on the two original clients and
   `nomad_node_role=ingress` on the new `nomad-consul-ingress-client-1`
   (public IP `3.137.180.227`), exactly as `inventory.tpl` was designed to
   emit.
3. `deploy_consul_nomad_wi.yaml` then `consul_nomad_service_mesh.yaml` both
   ran clean (zero failures) after the two fixes above.
4. `nomad node status -verbose <id> | grep nodeRole` confirmed
   `meta.nodeRole = ingress` on exactly one node (Nomad-assigned name
   `nomad-client-3`, since the ingress client is folded into the same
   sequential `nomad_clients.yaml` numbering as planned in §2) and
   `meta.nodeRole = internal` on the other two.
5. Stopped, purged, and redeployed `api-gateway.nomad.hcl` **three times**;
   every deployment landed on `nomad-client-3` and reached healthy on the
   first attempt each time — confirmed via `nomad alloc status | grep
   "Node Name"` after each redeploy.
6. Confirmed the security-group split directly: `curl` to
   `https://3.141.30.73:8447/` and `https://3.145.38.9:8447/` (the two
   internal clients) both timed out; `curl` to
   `https://3.137.180.227:8447/` (the ingress client) returned `HTTP 200`
   immediately.
7. Full functional check: 10/10 `curl -sk https://3.137.180.227:8447/`
   returned `HTTP 200` with the real Countdash page.

**Adjustment 3 — `ingress_client_count`'s default, found when asked "will
Options A-C still work as expected?" after the above was already verified.**
§1 above (and the `variable "ingress_client_count"` block as originally
written) defaulted it to `1`. That's fine for *this* cluster, but
`terraform.tfvars` is shared across every Option in `DEPLOY_CLUSTER_GUIDE.md`
— Terraform provisioning happens once, before any Option is chosen — so a
default of `1` would silently provision the extra instance and open `8447`
for Get Started/Option A/B/C/F too, none of which use or want it. Worst for
Get Started specifically, whose checklist already overrides `client_count =
0` for a true single-node setup but said nothing about
`ingress_client_count`. Fixed by changing `variables.tf`'s default to `0`
(this cluster's own `terraform.tfvars` still explicitly sets `1`, so nothing
about the already-verified deployment above changed — confirmed with
`terraform plan` showing no diff after the default changed) and adding an
explicit "set `ingress_client_count = 1` before provisioning" step to
Option E's checklist and prose section only, mirroring how Get Started's
`client_count = 0` override is already documented.

**Not done** (left as documented, intentional non-goals per the Context
section above): no NAT Gateway / true private subnet; the Nomad node name
for the ingress client stays the generic sequential `nomad-client-3` rather
than a distinct `nomad-ingress-client-1` (cosmetic only, doesn't affect the
constraint mechanism); the non-mesh Countdash/HashiCups job specs in
`consul-sd/`/`nomad-sd/` are untouched (Option E only, per the approved
scope decision).

## Addendum: simultaneous Countdash + HashiCups access (2026-07-22)

Follow-on question after the above: the gateway originally had **one**
listener (port 8447) with both `http-route-countdash.hcl` and
`http-route-hashicups.hcl` matching the identical, unqualified
`Path.Match = "prefix", Value = "/"` — so only whichever route was applied
last actually won, and Countdash/HashiCups could never both be reached at
the same time. The user wanted both open simultaneously in separate browser
windows, and explicitly ruled out a `Hostnames`/hosts-file-based fix.

**Fix: a second gateway listener on its own port**, rather than routing
rules. `gateway-listener.hcl` now declares two `Listeners` on the same
`api-gateway` config entry — `https-countdash` (port 8447) and
`https-hashicups` (port 8448), both referencing the same
`api-gateway-cert` inline-certificate (the cert's SAN is the ingress
node's IP, which doesn't vary by port). Each `http-route`'s `Parents[].
SectionName` now binds to its own listener instead of both sharing
`"https"`. `api-gateway.nomad.hcl`'s `network` block gained a second
`port` stanza (`https-hashicups`, static 8448), and
`aws_security_group.ingress_sg` (`terraform/aws/network.tf`) now opens
8448 as well as 8447 — still only on the dedicated ingress client, per the
plan above. No app job spec changes needed, unlike a path-prefix approach
would have required (Countdash and HashiCups both generate root-relative
asset URLs with no base-path support wired into either job spec, so
serving either one under a subpath like `/hashicups/` would likely have
broken their static assets/API calls).

**A pre-existing xDS bug (issue 6 in
[api-gateway-envoy-bootstrap-troubleshooting.md](api-gateway-envoy-bootstrap-troubleshooting.md))
recurred while verifying this**, and turned out to need a fuller fix than
first understood: after writing the two-listener config (even from the
server's own version-matched `consul` CLI this time), both ports returned
`503`/`no_cluster` — Envoy's RDS routes referenced cluster names missing
the `1a47f6e1~` hash prefix that CDS actually used. Simply overwriting the
config entries again didn't fix it. What did: **deleting** (not
overwriting) `http-route-countdash`, `http-route-hashicups`, and
`api-gateway`, recreating them, **and** a full `nomad job stop -purge` +
`nomad job run` of the gateway job (a task-level restart alone was not
enough). See the troubleshooting page's issue 6 update for the fuller
diagnosis — CLI version skew (the originally-suspected cause) is a
trigger, not the sole cause; this looks like a genuine staleness/race in
Consul API Gateway v2's own xDS controller.

**Verified live:** both apps simultaneously reachable — 10/10
`https://<ingress-ip>:8447/` returned Countdash's page, 10/10
`https://<ingress-ip>:8448/` returned HashiCups', in the same test run.

Files touched beyond the ones listed in this plan's Implementation section:
`nomad-jobs/consul-mesh/gateway-listener.hcl`,
`nomad-jobs/consul-mesh/http-route-countdash.hcl`,
`nomad-jobs/consul-mesh/http-route-hashicups.hcl`,
`nomad-jobs/consul-mesh/api-gateway.nomad.hcl`,
`terraform/aws/network.tf`, `nomad-jobs/consul-mesh/README.md`,
`DEPLOY_CLUSTER_GUIDE.md`.

## Addendum: Option E now works on Multipass too (2026-07-22)

This plan's Option E work had only ever run on AWS. `TEST_PLAN.md` (written
for PR #1 review) surfaced why it didn't work on Multipass at all:
`ansible/playbooks/consul_nomad_service_mesh.yaml` hardcoded
`consul_cloud_auto_join_enabled: true` (unlike every other Consul playbook
in this repo, which reads an overridable `consul_use_aws_cloud_join`), so
Consul tried to `retry_join` against the AWS EC2 API on Multipass VMs. And
`terraform/multipass/` had no `ingress_client_count` equivalent, so the
dedicated ingress node this plan's `constraint` block requires couldn't be
provisioned there at all.

**Fix**: the same two-line `consul_cloud_auto_join_enabled` pattern applied
to `consul_nomad_service_mesh.yaml`, plus `terraform/multipass/` gaining
`ingress_client_count` (`variables.tf`, `compute.tf`'s new
`multipass_instance.ingress_clients` + merged inventory map,
`inventory.tpl`'s `nomad_node_role` field, `outputs.tf`,
`terraform.tfvars.example`, `README.md`) — mirroring `terraform/aws/`'s
shape exactly, with one deliberate difference: **Multipass has no
security-group equivalent**, so `ingress_client_count` there only affects
Nomad scheduling metadata (`meta.nodeRole`), not network access — every
VM's ports are already reachable from the host regardless.

**Verified live on Multipass, 2026-07-22**: `deploy_consul_nomad_mesh.yaml`
completed `failed=0` across all 6 hosts (this is the real test of the fix —
it would have failed here with an AWS API error under the old hardcode).
`consul.connect = true` on every client, `meta.nodeRole = ingress` on
exactly the dedicated node, 3/3 gateway redeploys landed there, Countdash
reachable through the gateway (`HTTP 200` on 8447).

**Known limitation, not fixed here**: HashiCups' `hashicorpdemoapp/payments`
Docker image has no arm64 build (confirmed via `docker manifest inspect` —
single-architecture manifest, not a multi-arch list) and crash-loops with
`exec format error` on Apple Silicon Multipass VMs; `public-api`'s
deployment also fails as a downstream consequence. `db`, `product-api`,
`frontend`, and `nginx` all start healthy. This is a vendor-image gap
(same class of issue as `countdash-multipass-multiarch-fix.md`, but no
arm64 tag exists to switch to this time), not something fixable in this
repo's code short of adding QEMU/binfmt emulation to the Multipass VMs. The
dual-listener change itself is still fully verified via Countdash alone —
HashiCups is only affected by this pre-existing, unrelated image gap.

**Also found and fixed along the way** (Option F, live-verified in the same
session): Vault 1.20+ requires `disable_mlock` set explicitly or
`vault.service` crash-loops — fixed in `ansible/roles/vault/`. Not
Multipass-specific; would have hit AWS too, just hadn't been exercised live
before. See `_context/wiki/multipass-local-testing-plan.md` for the fuller
writeup of both the Vault fix and the Option D/F verification.

Files touched: `ansible/playbooks/consul_nomad_service_mesh.yaml`,
`terraform/multipass/{variables.tf,compute.tf,inventory.tpl,outputs.tf,
terraform.tfvars.example,README.md}`,
`nomad-jobs/consul-mesh/README.md`,
`ansible/roles/vault/{defaults/main.yaml,templates/vault.hcl.j2,README.md}`.
