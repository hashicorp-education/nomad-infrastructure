# Countdash: multi-arch fixes extended to all 3 specs + a job-ID collision (2026-07-21)

Follow-on to [countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md),
which fixed `countdash-consul-service-discovery.nomad.hcl` only. Applying the
same fixes to the other two Countdash job specs
(`countdash-nomad-service-discovery.nomad.hcl`,
`countdash-consul-service-mesh.nomad.hcl`) surfaced a third, unrelated bug:
two of the three specs silently shared a Nomad job ID.

## 1. Same fixes applied to the other two specs

**`countdash-nomad-service-discovery.nomad.hcl`** had both problems described
in the linked page:

- `service.address` used `attr.unique.platform.aws.local-ipv4` /
  `attr.unique.platform.aws.public-hostname` — AWS-only, absent on Multipass.
  Replaced with `attr.unique.network.ip-address` on both.
- `image = "hashicorpdev/counter-api:v3"` / `"hashicorpdev/counter-dashboard:v3"`
  — amd64-only tags. Added `countdash-api-version` / `countdash-web-version`
  variables (default `v3`) and interpolated
  `"hashicorpdev/counter-api:${var.countdash-api-version}-${attr.cpu.arch}"`
  (and the dashboard equivalent), same as the Consul-DNS variant.

**Verified live**: deployed to the real cluster, `Status = successful`, both
groups `Healthy = 1`.

**`countdash-consul-service-mesh.nomad.hcl`** only needed the image fix — its
`service` blocks use bridge networking + Consul Connect sidecars with no
explicit `address` field at all, so the AWS-attribute bug doesn't apply
there. Added the same two version variables and interpolated
`${attr.cpu.arch}` into both `image` fields.

**Not live-deployed**: this spec requires the full Consul service mesh setup
(service-defaults, intentions, API Gateway — see
`nomad-jobs/consul-mesh/README.md`), which isn't provisioned on this
particular test cluster (built for the plain service-discovery scenario).
Validated with `nomad job validate` only; trust the mesh-specific behavior
as unverified until deployed against a cluster with the mesh scenario
actually running.

## 2. Job-ID collision discovered mid-verification

Deploying `countdash-nomad-service-discovery.nomad.hcl` to verify its fix
**silently overwrote** the already-running
`countdash-consul-service-discovery.nomad.hcl` deployment. Both files
declared:

```hcl
job "countdash" {
```

Same job ID, same namespace → Nomad treated the second `nomad job run` as an
**in-place update of the same job** (version 0 → version 1), not a separate
deployment. `nomad job status` showed a single `countdash` job whose task
group contents had just changed out from under the first deployment — no
error, no warning, both `nomad job validate` runs had passed cleanly on
their own since job-ID uniqueness is a runtime/registry concern, not a
parse-time schema check.

Recovered via `nomad job history -p countdash` (version 0 was still intact
and revertible), but the better fix is structural: give every distinct
Countdash variant its own job ID so this can't recur.

**Fix**: renamed job IDs to be unique per file:

| File | Old job ID | New job ID |
|------|-----------|------------|
| `countdash-consul-service-discovery.nomad.hcl` | `countdash` | `countdash-consul-sd` |
| `countdash-nomad-service-discovery.nomad.hcl` | `countdash` | `countdash-nomad-sd` |
| `countdash-consul-service-mesh.nomad.hcl` | `countdash-mesh` | *(unchanged — already unique)* |

Also updated `README.md`'s `job` block doc example (was illustrating with
the now-stale `job "countdash" { ... }` snippet) to use
`countdash-consul-sd` and explain why the two job names differ.

**Verified live**: stopped the collided job, redeployed both renamed specs
back-to-back — both now show as independent entries in `nomad job status`
(`countdash-consul-sd`, `countdash-nomad-sd`), both `Status = successful`,
no further interference.

## Takeaway

**A clean `nomad job validate` does not guarantee a job won't collide with
another job already using the same ID.** Job-ID uniqueness is enforced at
`nomad job run` time against the live job registry, not by the HCL parser
against other files on disk. When a repo has multiple job spec files meant
to be deployable independently (variants of the same demo app, in this
case), grep the repo for the literal job ID before assuming each file is
self-contained:

```bash
grep -rn '^job "' nomad-jobs/consul-sd/*.hcl nomad-jobs/nomad-sd/*.hcl nomad-jobs/consul-mesh/countdash*.hcl
```

## Related

- [countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md) —
  the original fix (Consul-DNS variant only) that this page extends to the
  other two specs.
- `nomad-jobs/consul-mesh/README.md` — deploy order required before
  `countdash-consul-service-mesh.nomad.hcl` can be verified live (not done
  this session).
