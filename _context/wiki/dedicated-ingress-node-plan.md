# Plan: Dedicated public "ingress" Nomad client for the API Gateway

**Status: proposed, not yet implemented.** Approved by the user 2026-07-21;
implementation deferred to a future session.

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
