# TLS enabled by default for Consul + Nomad — reasoning and plan

Goal: flip `consul_tls_enabled` / `nomad_tls_enabled` to `true` by default across
all four deploy entrypoints, fixing gaps found along the way. Test path:
`deploy_consul_nomad_sd.yaml` then `nomad-jobs/consul-sd/hashicups.nomad.hcl`.

## Findings

- Nomad's `tls{}` block in `roles/nomad/templates/nomad.hcl.j2` was already correct
  and complete (`http=true rpc=true verify_server_hostname=true
  verify_https_client=false`) — nothing to change there.
- **Bug**: `playbooks/nomad_servers.yaml` had two `tls` role invocations — one
  correctly gated by `when: nomad_tls_enabled`, and a second **unconditional**
  one that always generated a node cert using `dns: "client.global.nomad"`
  (wrong SAN for a server; also ran even when TLS was disabled). Fixed by
  consolidating into a single conditional entry with `dns: "server.global.nomad"`.
- **Gap**: Consul's `tls{}` block existed in `roles/consul/templates/consul.hcl.j2`
  but `playbooks/consul_servers.yaml` / `consul_clients.yaml` never invoked the
  `tls` or `helper` roles to generate/distribute certs — Consul TLS was
  unreachable in practice. Built from scratch, mirroring the Nomad pattern.
- Nomad has no independent HTTP/HTTPS ports — enabling `tls.http=true` forces
  ALL traffic (including loopback) through TLS. Consul, by contrast, supports
  an `addresses{}` block that lets HTTP and HTTPS bind to different
  interfaces, enabling a hybrid loopback-HTTP + external-HTTPS setup.

## Decisions

- **Consul access model = hybrid**: plain HTTP kept on `127.0.0.1:8500` for
  local automation (Ansible ACL/bootstrap tasks, Nomad's own `consul{}`
  integration block) and HTTPS exposed externally on `0.0.0.0:8443`.
- **Client cert policy = CA trust only**: `verify_incoming`/`verify_https_client
  = false` on the HTTP(S) API side for both Consul and Nomad — no client cert
  needed to call the API/UI/CLI. Internal RPC/gossip stays full mTLS
  (`verify_incoming/outgoing/verify_server_hostname = true`). Security on the
  API side is enforced by ACLs (already default-deny), not by client-cert
  gating.
- **Consul HTTPS port = 8443** (not Consul's own 8501 default) — matches the
  sibling `learn-consul-nomad-vm` project's convention in this workspace.
- **Cert distribution = operator method** (manual generation via the existing
  `tls` role + distribution via the `helper` role) for both Consul and Nomad,
  on all nodes — not Consul's `auto_encrypt`/Connect-CA mechanism. Reuses the
  pattern already proven for Nomad.
- Cert SANs: Nomad keeps `server.global.nomad` / `client.global.nomad`
  (region+role convention). Consul uses
  `server.{{ consul_datacenter }}.{{ consul_domain }}` /
  `client.{{ consul_datacenter }}.{{ consul_domain }}`, i.e. `server.dc1.global`.
- Fresh-deploy scenario assumed — no live-cluster TLS migration steps needed.

## Explicitly out of scope

- `_context/wiki/*.md` historical troubleshooting notes (this file aside).
- Consul Connect / service mesh, gossip encryption, ACL enable/disable defaults.
- `nomad-jobs/**` job specs — Nomad's own loopback `consul{}` integration
  shields jobs from the Consul TLS change.
- Remote Terraform backend.

## Implementation phases

1. **Terraform** — `network.tf` (add 8443 ingress), `outputs.tf` (https UI
   URLs), `terraform/aws/README.md`.
2. **Fix + enable Nomad TLS** — consolidate the `nomad_servers.yaml` bug;
   flip `nomad_tls_enabled` defaults/playbook vars to `true`.
3. **Wire Consul TLS** — `consul_addr_http`/`consul_addr_https` vars,
   `addresses{}` block, split `tls.https{}`/`tls.internal_rpc{}` stanzas in
   `consul.hcl.j2`; add `tls` + `helper` role invocations to
   `consul_servers.yaml`/`consul_clients.yaml`.
4. **Downstream Nomad re-render playbooks** —
   `consul_nomad_service_discovery.yaml`, `consul_nomad_workload_identity.yaml`,
   `nomad_acl_bootstrap.yaml` (https address + `NOMAD_CACERT`).
5. **Operator tooling** — `cluster_summary.yaml`, `set-cluster-env.sh` /
   `unset-cluster-env.sh` (https + CACERT export/unset).
6. **Documentation** — top-level `README.md`/`AGENTS.md`/
   `DEPLOY_CLUSTER_GUIDE.md`, `ansible/README.md`,
   `ansible/PLAYBOOKS-README.md`, role READMEs (`consul`, `nomad`, `tls`,
   `helper`), `ansible/README-SECURITY-GROUP.md`, and the two
   `.github/instructions/*.md` files.

## Verification

- `terraform plan`; `ansible-playbook --syntax-check` on modified playbooks.
- Full deploy: `terraform apply` → `ansible-galaxy install -r requirements.yaml`
  → `ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml`.
- On a server: `consul validate /etc/consul.d`; verify TLS via
  `CONSUL_HTTP_ADDR=https://127.0.0.1:8443 CONSUL_CACERT=/etc/consul.d/tls/ca.pem
  consul members`; verify loopback automation still works over plain HTTP on
  8500.
- Verify Nomad via `NOMAD_ADDR=https://127.0.0.1:4646
  NOMAD_CACERT=/etc/nomad.d/.tls/ca.crt nomad server members`.
- `source ansible/set-cluster-env.sh`, deploy
  `nomad-jobs/consul-sd/hashicups.nomad.hcl`, confirm allocations healthy and
  the app reachable; browse both UIs over https.
- Confirm `.global` DNS resolution via dnsmasq is unaffected.
