# Transparent proxy vs. explicit `upstreams` (2026-07-21)

Q&A captured from a discussion about `nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl`
(named `countdash-consul-service-mesh.nomad.hcl`, then
`countdash-consul-service-mesh-upstreams.nomad.hcl`, at the time this page
was first written — renamed twice since) and
`hashicups-consul-service-mesh.nomad.hcl`, both of which used explicit
`upstreams` blocks at the time (a deliberate choice — see
[consul-service-mesh-plan.md §6](consul-service-mesh-plan.md#6-networking-readiness-cni-bridge-mode)).
**Since superseded for Countdash**: `transparent_proxy` is now the default
mesh mode for Countdash (`countdash-transparent-proxy.nomad.hcl`), per
[transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md) —
`countdash-upstreams.nomad.hcl` remains available as the documented
alternative. HashiCups' mesh job is unaffected and still uses `upstreams`
only. Captured here since it's genuinely useful background for anyone
evaluating whether to switch, without re-deriving it. See also the
[Nomad service mesh tutorial](https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-service-mesh)
and [Consul's transparent proxy docs](https://developer.hashicorp.com/consul/docs/connect/proxy/transparent-proxy/vm).

## How the two mechanisms differ

- **Explicit `upstreams`** (what this repo's mesh job specs use): each
  downstream dependency is declared by name and bound to a specific local
  port, e.g. `countdash-web`'s sidecar binds `countdash-api` to
  `127.0.0.1:9001`. The app is rewritten to call that loopback port instead
  of the real service — see `COUNTING_SERVICE_URL =
  "http://127.0.0.1:${var.countdash-api-port}"` in
  `countdash-upstreams.nomad.hcl`. Envoy only intercepts
  the specific ports declared; nothing else is touched.

- **`transparent_proxy`**: Envoy uses `iptables` rules (installed via the
  separate `consul-cni` CNI plugin at network-namespace setup time) to
  silently redirect *all* outbound traffic from the task into the mesh,
  matched by destination rather than a hardcoded local port. The app keeps
  calling the real service address/name as if there were no mesh at all — no
  URL rewiring needed.

| | `upstreams` (explicit) | `transparent_proxy` |
|---|---|---|
| App changes required | Yes — rewire URLs to `127.0.0.1:<port>` | No — app is mesh-unaware |
| Traffic visibility | Every dependency spelled out in the job spec | Implicit — must inspect iptables/Envoy config to know what's intercepted |
| Infra prerequisite | Standard CNI plugins only (already installed) | Requires the separate `consul-cni` plugin (not installed in this repo) |
| Failure mode if misconfigured | Connection refused — fails loud | Can silently intercept traffic that wasn't meant to be meshed (e.g. DNS lookups, health-check probes) |

Neither is universally "better" — this repo picked explicit `upstreams`
because it matches the existing convention of spelling out configuration
rather than relying on implicit/auto-discovery behavior (Consul DNS names
are already fully spelled out in the service-discovery job specs, for the
same reason).

**Update:** the `consul-cni` gap described below has since been closed and
transparent proxy is now the **default** mesh mode for Countdash — see
[transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md)
for what shipped and was live-verified, including the two manual steps
(Nomad client restart, gateway ACL policy) that were later automated too.
The explanation below of *why* it didn't work before that change is still
accurate background.

## Why the mesh job specs couldn't use `transparent_proxy` before this

Confirmed by reading the actual Ansible CNI setup, not just assumption:
[ansible/roles/cni/tasks/install.yaml](../../ansible/roles/cni/tasks/install.yaml)
installs the **standard** CNI plugin bundle (bridge, portmap, host-local,
etc. — pinned to `cni_plugins_version: 1.9.1` in
[group_vars/all.yaml](../../ansible/group_vars/all.yaml)). That's sufficient
for `network.mode = "bridge"` plus `connect.sidecar_service` with explicit
`upstreams`. It is **not** sufficient for `transparent_proxy`, which
specifically requires the separate `consul-cni` plugin — not referenced
anywhere in this repo's Ansible. Trying to run `transparent_proxy {}` as-is
would fail at Envoy/CNI bootstrap, not silently misroute traffic.

## Does enabling transparent proxy support break existing `upstreams` jobs?

No — **it's opt-in per task group, not a cluster-wide switch.** The
`upstreams`-vs-`transparent_proxy` choice lives entirely inside each job
spec's `connect.sidecar_service.proxy` block. There is no Consul
agent-level or `connect { enabled = true }`-level setting that forces every
sidecar into one mode.

Practical implication: once `consul-cni` is installed and transparent-proxy
capability is enabled on the clients,

- `countdash-upstreams.nomad.hcl` and
  `hashicups-consul-service-mesh.nomad.hcl` keep working completely
  unmodified — their `upstreams` blocks never invoke `consul-cni`.
- New jobs (or new versions of these same jobs) can opt into
  `transparent_proxy {}` instead; Nomad only invokes `consul-cni` for the
  specific allocation that requests it.
- The two modes can even coexist **within one job** — e.g. `countdash-api`
  on `upstreams`, `countdash-web` on `transparent_proxy` — since the mode is
  a per-task-group proxy setting.

So installing `consul-cni` and turning on transparent-proxy support is
purely additive: it unlocks the option for services that want it, without
changing the mesh behavior of any service that doesn't opt in.

## Related

- [consul-service-mesh-plan.md](consul-service-mesh-plan.md) — the original
  decision to use explicit `upstreams`, and current state of the mesh
  implementation (fully deployed and verified, Steps 0–8 done).
- `nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl` /
  `hashicups-consul-service-mesh.nomad.hcl` — the job specs this question was
  asked about.
- [transparent-proxy-enablement-plan.md](transparent-proxy-enablement-plan.md) —
  what actually shipped to close the `consul-cni` gap: the extended
  `ansible/roles/cni/` role and the new
  `countdash-transparent-proxy.nomad.hcl` job spec.
