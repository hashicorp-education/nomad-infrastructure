# Plan: Enable Consul Connect transparent proxy support (2026-07-21)

**Status: implemented and verified end-to-end on the live AWS cluster.**
Three real bugs were found and fixed along the way — none in the original
plan's scope, all only surfaced because transparent proxy actually depends
on DNS resolution working correctly, unlike the `upstreams` variant. See
"Bugs found during live rollout" below. Follow-on to
[transparent-proxy-vs-upstreams.md](transparent-proxy-vs-upstreams.md), which
established that `transparent_proxy` mode is opt-in per task group, not a
cluster-wide switch — so it can be added alongside the existing
`upstreams`-based mesh job specs without touching them. This page documents
what shipped and what's left to verify live.

## The actual gap

Everything except one piece was already in place from Option E: Consul
Connect enabled (`consul_connect_enabled`), gRPC-TLS
(`consul_port_grpc_tls: 8503`), bridge networking, dnsmasq `.consul` DNS
resolution. The one missing piece, confirmed by reading the actual role
(`ansible/roles/cni/tasks/install.yaml`, `defaults/main.yaml`): the `cni`
role only installs the standard `containernetworking/plugins` tarball
(bridge, portmap, host-local, etc.), pinned to `1.9.1`. Nomad's
`transparent_proxy` mode additionally requires the separate `consul-cni`
binary (published at
[releases.hashicorp.com/consul-cni](https://releases.hashicorp.com/consul-cni)) —
not installed anywhere in this repo before this change.

## What did *not* need to change

- **`ansible/roles/consul/templates/consul.hcl.j2`** — no agent-level
  `transparent_proxy` sub-block exists in Consul's agent HCL schema (that
  setting is a Consul-on-Kubernetes Helm value,
  `connectInject.transparentProxy.defaultEnabled`, not applicable to a bare
  Consul agent). The existing `connect { enabled = true }` block was already
  sufficient — left unmodified.
- **`ansible/roles/nomad/templates/nomad.hcl.j2`** — Nomad's
  `client.cni_path` / `client.cni_config_dir` default to `/opt/cni/bin` /
  `/opt/cni/config`, already matching where the `cni` role installs plugins.
  Bridge-mode mesh already worked before this change without setting these
  explicitly, confirming the defaults are in effect. Left unmodified —
  verify post-rollout (see below) rather than assuming.
- **Existing mesh job specs** — per this repo's established convention
  ("Existing job specs... not modified. All service mesh functionality
  ships as new files.", from
  [consul-service-mesh-plan.md](consul-service-mesh-plan.md)),
  `countdash-upstreams.nomad.hcl` was not touched; a new
  file was added instead.
- **Consul intentions / service-defaults** — transparent proxy still
  authorizes via the same intentions on the same service names; no changes.

## What shipped

### 1. `ansible/roles/cni/` — install `consul-cni`

- `defaults/main.yaml`: new `consul_cni_enabled` (default `false`),
  `consul_cni_version` (`1.6.2` — provisional, same caveat as
  `consul_binary_version` elsewhere in this repo: not yet re-verified against
  the actual installed Consul/Nomad binary versions), `consul_cni_url`
  following HashiCorp's release naming
  (`consul-cni_<version>_<os>_<arch>.zip`, a single-binary zip — distinct
  from the multi-plugin tarball `cni_plugins_url` already used), reusing the
  existing `cni_plugins_arch_map` (`x86_64→amd64`, `aarch64→arm64`).
- New `tasks/install_consul_cni.yaml`: downloads and unzips directly into
  `cni_plugins_path` (same directory as the standard plugins — Nomad
  discovers all plugins from one `cni_path`). Mirrors the structure of the
  existing `tasks/install.yaml`.
- `tasks/main.yaml`: checks for `{{ cni_plugins_path }}/consul-cni`
  independently of the standard-plugins directory-exists check, and installs
  it when `consul_cni_enabled: true` and the binary isn't already present —
  so re-running this role on a cluster that already has the standard plugins
  correctly adds just the missing piece, idempotently.
- `README.md` updated to document the new binary and variable, and to be
  explicit that it's **not** needed for the default `upstreams`-based mesh.
- `group_vars/all.yaml`: `consul_cni_version` pinned centrally, matching the
  existing single-source-of-truth pattern used for `cni_plugins_version`.

### 2. `ansible/playbooks/consul_nomad_service_mesh.yaml` — wire it in

Play 2 (clients — the play that already sets `consul_connect_enabled: true`,
`consul_port_grpc_tls: 8503`, etc.) gained a second role entry:

```yaml
roles:
- role: consul
- role: cni
  vars:
    consul_cni_enabled: true
```

Scoped to this playbook only — the base `nomad_clients.yaml` client
bring-up playbook is unchanged, so `consul-cni` stays specific to clusters
that opt into the mesh scenario, matching how every other Connect-only
setting in this repo is scoped.

### 3. New job spec: `countdash-transparent-proxy.nomad.hcl`

New file in `nomad-jobs/consul-mesh/`, copied from
`countdash-upstreams.nomad.hcl` with the job renamed to
`countdash-mesh-tproxy` (avoids an ID collision with `countdash-mesh-upstreams`
— this repo has hit that exact bug twice already, see
[countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md)).
Two changes from the base file:

- `countdash-web`'s `connect.sidecar_service.proxy` block:
  `upstreams { destination_name = "countdash-api" ... }` replaced with
  `transparent_proxy {}`.
- `countdash-web`'s `COUNTING_SERVICE_URL` env var: changed from the fixed
  loopback bind (`http://127.0.0.1:${var.countdash-api-port}`) to the real
  Consul DNS name, matching the exact suffix convention already used
  throughout `nomad-jobs/consul-sd/*.hcl` (confirmed via grep across that
  directory): `http://countdash-api.service.dc1.global:${var.countdash-api-port}`.
  Transparent proxy intercepts based on the real destination address, so the
  app must call the real name rather than a fixed local port.

`countdash-api`'s group is unaffected — it was already a bare
`sidecar_service {}` with no upstream on that side, same as before.

`nomad job validate` passes clean on this file.

### 4. Docs

- This page.
- `nomad-jobs/consul-mesh/README.md`: new "Step 7b" section documenting the
  variant and its extra `consul-cni` prerequisite, plus a file-index row and
  a clean-up command. Also fixed a stale cross-reference found while editing
  (pointed at the pre-reorganization `../hashicups/` path — corrected to
  `../consul-sd/` and `../nomad-sd/`).
- `transparent-proxy-vs-upstreams.md`'s "Related" section updated to point
  here.

## Rollout / verification — done, live on the AWS cluster

All steps verified against the real 3-server/2-client AWS cluster (Consul
v1.19.1, Nomad v2.0.4):

0. **Version check**: confirmed via `releases.hashicorp.com/consul-cni` that
   `1.6.2` is a real, published release (not a guess) before installing it.
   No formal consul-cni/Consul-core compatibility matrix exists publicly;
   proceeded and treated any bootstrap failure as the empirical signal, per
   this repo's established posture for provisional version pins — none
   occurred. `consul-cni --version` on both clients confirms `v1.6.2`.
1. Ran `ansible-playbook -i inventory.ini playbooks/consul_nomad_service_mesh.yaml`
   against the real clients. `consul-cni` installed to `/opt/cni/bin` on
   both — but did **not** immediately fingerprint (see Bug 1 below); fixed,
   then confirmed `plugins.cni.version.consul-cni = v1.6.2` via
   `nomad node status -verbose`.
2. Deployed `countdash-transparent-proxy.nomad.hcl`. First attempt failed
   placement entirely (Bug 1), then failed at the app layer after placing
   (Bugs 2 and 3). Final state: both groups healthy, `connect-proxy-*`
   sidecar logs show clean Envoy bootstrap (`outbound_listener:127.0.0.1:15001`
   listening, no errors).
3. **Functional check**: after fixing Bugs 2 and 3 and clearing a stale
   catalog entry (Bug 4), 15/15 consecutive `curl -sk https://<client-ip>:8447/`
   requests returned HTTP 200 with the real Countdash HTML. Directly
   confirmed the mesh hop itself (not just the gateway) via
   `nomad alloc exec -task countdash-web ... wget http://countdash-api.virtual.global:9001/actuator/health`
   from inside the `countdash-web` container — returned a real, incrementing
   counter (`{"count":206...}`, `207`, `208`) on repeated calls, proving
   traffic actually reaches `countdash-api` through the transparent-proxied
   Envoy sidecar path, not just that the alloc is up.
4. **Negative check**: `consul intention delete countdash-web countdash-api`
   → `consul intention check` flipped to `Denied`, and the same in-container
   `wget` to `countdash-api.virtual.global` immediately started failing with
   `Connection reset by peer` — proving intentions enforce identically for
   transparent-proxied traffic as for explicit `upstreams` traffic, not a
   separate/weaker enforcement path. Restored the intention
   (`consul config write intentions/countdash-api.hcl`) and re-confirmed
   `Allowed` + working traffic before finishing.

## Bugs found during live rollout

None of these were anticipated in the original plan — all four surfaced
only because transparent proxy actually requires DNS resolution and a
correctly-fingerprinted CNI plugin to function, unlike `upstreams`, which
needs neither.

**Bug 1 — Nomad doesn't re-fingerprint CNI plugins on a running agent.**
Installing the `consul-cni` binary onto an already-running Nomad client has
no effect until the Nomad **client process itself** is restarted — Nomad
scans `/opt/cni/bin` for plugins at agent startup only, not on a timer or on
file-change. Symptom: `countdash-web`'s placement failed outright with
`Constraint "${attr.plugins.cni.version.consul-cni} semver >= 1.4.2": 2
nodes excluded by filter`, even though the binary was present, executable,
and reported the right version when run directly. Confirmed by comparing
`nomad node status -verbose` before/after a manual `systemctl restart
nomad` on both clients — the attribute only appeared after the restart.
**Not yet automated**: `consul_nomad_service_mesh.yaml`'s `cni` role
install doesn't currently trigger a Nomad client restart (no relevant
`notify` handler wired up, since Play 2 uses the `cni`/`consul` roles, not
the `nomad` role). On a cluster where Nomad is already running when this
playbook is first applied with `consul_cni_enabled: true` (the common case,
same as this rollout), a **manual `systemctl restart nomad` on every Nomad
client is required** after running the playbook, before transparent-proxy
jobs will place. Documented here rather than automated, to avoid changing
this playbook's restart semantics without being able to fully test both
the fresh-cluster and already-running-cluster cases in one pass.

**Bug 2 — `consul_nomad_service_mesh.yaml` silently regressed Consul DNS.**
Its Play 1 (servers) and Play 2 (clients) re-render `consul.hcl` and
restart Consul, but neither play supplied `consul_acl_dns_token` — only
`consul_dns_token.yaml`'s Play 3 did, days/sessions earlier, via a
*runtime* `consul acl set-agent-token dns ...` call. That runtime-set token
doesn't survive a Consul process restart if the **static** config lacks
it, and static config is exactly what this playbook re-renders. Result:
every DNS query answered with the effectively-anonymous token, which is
denied (`consul_acl_deny_anonymous.yaml`), silently returning **NXDOMAIN
for every service name** — confirmed directly with `dig @127.0.0.1 -p 8600
countdash-api.service.dc1.global` returning `NXDOMAIN` despite the service
being registered and healthy. This is the same class of bug already
documented for `nomad_client_use_consul_token` in
[acl-architecture.md §10](acl-architecture.md#10-common-acl-failure-modes)
and the wiki's "Consul token fallback" established pattern: **a var must be
re-supplied in every play that re-renders the same config file, not just
the play that originally set it.** Fixed by adding the same `pre_tasks`
(read `tokens/consul-dns-secret-id.txt`, `set_fact consul_acl_dns_token`)
to both Play 1 and Play 2 of `consul_nomad_service_mesh.yaml`, mirroring
`consul_dns_token.yaml` Play 3 exactly. Only affected transparent proxy in
this rollout (the `upstreams` variant never does a DNS lookup at all — it
calls a fixed `127.0.0.1:<port>`), but the regression itself hits *any*
Consul DNS consumer and would silently break under any similar config
re-render.

**Bug 3 — wrong DNS name for transparent-proxy interception.**
Even after Bug 2 was fixed, DNS resolved fine but traffic still didn't
reach `countdash-api` — `wget` from inside `countdash-web` got `Connection
reset by peer`. Root cause: the job spec's `COUNTING_SERVICE_URL` used the
same DNS name convention as the `upstreams`/service-discovery job specs,
`countdash-api.service.dc1.global` — the **classic Consul catalog DNS
name**, which resolves to the service's real backing IP. `consul-cni`'s
`iptables` interception rules only redirect traffic destined to a Consul
**virtual IP** (the `240.0.0.0/8`-range addresses seen earlier in the
sidecar-proxy's `TaggedAddresses.consul-virtual`), not to real backing
IPs — so a plain catalog-DNS lookup produces an address transparent proxy
was never going to intercept in the first place, regardless of whether the
iptables rules themselves were correct. The fix is Consul's **virtual-IP
DNS name**: `<service>.virtual.<domain>` (this cluster's configured
`consul_domain` is `"global"`, not the default `"consul"`, so
`countdash-api.virtual.consul` returns `REFUSED` — confirmed live — while
`countdash-api.virtual.global` correctly returns `240.0.0.1`). Updated
`COUNTING_SERVICE_URL` to `http://countdash-api.virtual.global:...`; the
in-container `wget` immediately started returning real, incrementing
counter values. This is a genuinely non-obvious HashiCorp DNS-naming
distinction worth not re-discovering later — worth cross-referencing from
any future job spec that mixes `upstreams`/service-discovery DNS names
with `transparent_proxy`.

**Bug 4 — stale Consul catalog entries from redeploys (same class as
`api-gateway-envoy-bootstrap-troubleshooting.md`).** Hit twice in this
rollout alone: once from earlier same-session job stops leaving
`countdash-web`/`countdash-api`-sidecar entries registered and "passing"
under old, no-longer-running alloc IDs (inflating `passing` instance counts
and polluting `TaggedAddresses.consul-virtual` port mappings); once more
right after redeploying `countdash-transparent-proxy.nomad.hcl` with the
Bug 3 fix — the just-stopped previous `countdash-web` alloc stayed
registered as `passing`, and the API Gateway's Envoy load-balanced between
it (dead → `503`) and the live one (`200`), producing an intermittent
~40-60% failure rate through the gateway that had nothing to do with
transparent proxy itself. Fixed both times with the same documented
pattern: `curl -X PUT .../v1/catalog/deregister` for the stale
`ServiceID`/`Node` pairs (Nomad's own anti-entropy sync doesn't clean up
entries for allocations it no longer knows about, and the local agent's
loop doesn't proactively catch this either).

**Also encountered while rebuilding the API Gateway from scratch (not a
transparent-proxy bug specifically, but blocking on the way to Step 3)**:
the gateway job's `nomad var get` template call for its Consul CA cert
failed (`Missing: nomad.var.block(...)`) with zero Nomad ACL policies
present on the cluster (`nomad acl policy list` → none) — the gateway
task's workload identity had no grant to read its own Nomad Variable.
Fixed with a workload-associated policy scoped to exactly this job:
`nomad acl policy apply -namespace ingress -job api-gateway -group gateway
-task gateway api-gateway-variables <policy-granting-read-on-nomad/jobs/api-gateway/gateway/*>`.
Not folded into this rollout's Ansible changes since it's a one-time
cluster-state fact (an ACL policy, not a config file), and out of scope for
the transparent-proxy feature itself — noted here since it will recur for
anyone rebuilding the gateway job on a cluster that's had its Nomad ACL
policies reset. Worth a follow-up cross-reference in
[api-gateway-envoy-bootstrap-troubleshooting.md](api-gateway-envoy-bootstrap-troubleshooting.md)
as a fifth bootstrap issue.

## Follow-ups

- Automate the Bug 1 Nomad-client-restart requirement (conditional handler
  tied to the `cni` role's consul-cni install task reporting `changed`)
  instead of leaving it as a documented manual step.
- Add the Bug 4 workload-associated ACL policy to
  `ansible/playbooks/consul_nomad_service_mesh.yaml` Play 4 (alongside the
  existing `ingress` namespace + gateway binding-rule creation), so
  rebuilding the API Gateway job doesn't require a manual `nomad acl policy
  apply` every time.
- `DEPLOY_CLUSTER_GUIDE.md`'s Option E section now has a short "Transparent
  proxy variant" subsection (see below) documenting the job spec and its
  one extra prerequisite (`consul-cni` + the Bug 1 client restart).

## Related

- [transparent-proxy-vs-upstreams.md](transparent-proxy-vs-upstreams.md) —
  the conceptual explainer this plan implements against.
- [consul-service-mesh-plan.md](consul-service-mesh-plan.md) — the base
  Option E mesh this extends; also the source of the "new files, don't
  modify existing job specs" convention followed here.
- [countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md) —
  why the new job spec uses a distinct job ID (`countdash-mesh-tproxy`).
- `ansible/roles/cni/` — the role extended in this change.
- `nomad-jobs/consul-mesh/countdash-transparent-proxy.nomad.hcl` — the new
  job spec.
