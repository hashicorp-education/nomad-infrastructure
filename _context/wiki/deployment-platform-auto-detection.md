# Automatic AWS/generic platform detection for job specs (2026-07-21)

Follow-on to [countdash-aws-public-address-fallback.md](countdash-aws-public-address-fallback.md),
which added a `countdash-web-platform` job variable (manual `-var` flag) so
`countdash-web` could register its real EC2 public hostname on AWS instead
of a private IP. The user's fair complaint: it's easy to forget the `-var`
flag, and forgetting it fails silently (see that page's "Sharp edge"
section). Asked for something automatic instead, expanded to every affected
job spec, and thoroughly documented — this page is that documentation.

## The idea that didn't work: node-level `meta`/`attr` as the ternary condition

First approach tried: have Ansible set client-level metadata
(`client { meta { platform = "aws" } }` in `nomad.hcl`, or dynamically via
`nomad node meta apply`) automatically per platform — since Ansible already
distinguishes AWS vs. Multipass for other purposes
(`consul_use_aws_cloud_join`) — and change the job spec's ternary condition
from `var.countdash-web-platform` to `meta.platform`. This would have meant
zero shell setup, zero variables, zero flags: the cluster itself would
"know" its own platform.

**Tested live before committing to it, and it doesn't work — not what was
assumed.** On a real AWS cluster (this repo's Multipass workspace had
already been destroyed to test on AWS, so this was tested for real, not
simulated):

1. `nomad node meta apply -node-id <id> platform=aws` — set dynamic node
   metadata for a live empirical test (the eventual real fix would use the
   static `client.meta` config instead, but this is the fast way to test the
   *mechanism* without an Ansible/config-reload round trip).
2. Deployed a throwaway test job with
   `address = meta.platform == "aws" ? attr.unique.platform.aws.public-hostname : attr.unique.network.ip-address`,
   constrained to that exact node. **Result: registered the private IP** —
   the `"aws"` branch was not selected, even though `meta.platform` really
   was `"aws"` on that node.
3. Control test, same node, same meta key: a `constraint { attribute =
   "${meta.platform}" value = "aws" }` block **correctly matched** and
   allowed placement — proving `meta.platform` genuinely does represent
   real node metadata, correctly, in this Nomad version. The metadata isn't
   the problem.
4. Tried a second variant to see if the issue was specific to `meta.*` or
   applied to any runtime-resolved condition: `address = attr.cpu.arch ==
   "amd64" ? attr.unique.platform.aws.public-hostname : attr.unique.network.ip-address`
   on the same node (confirmed genuinely amd64 via `nomad node status
   -verbose`). **Same result** — private IP registered, `"aws"` branch not
   selected, no error either time.

**Conclusion**: Nomad's `service.address` field only resolves a ternary
correctly when its *condition* is a `var.*` value — known at job-submission
time, before any node is chosen. A condition built from any node-runtime
value (`attr.*` or `meta.*`) silently resolves to the false branch, with
*no error at all* — worse than the already-documented footgun in
[countdash-aws-public-address-fallback.md](countdash-aws-public-address-fallback.md),
since that one at least produces a broken literal string and a decodable
health-check error; this one just quietly does the wrong thing. This is a
hard constraint of this Nomad version's job-spec HCL2 decoding for this
field — not a configuration mistake, and not something achievable by
setting node metadata more carefully. (The ternary's two *branches*, i.e.
the actual address values, are still resolved per-node at runtime exactly as
documented in the earlier page — it's specifically the *condition* that
must be parse-time-known.)

This means the earlier page's `var.*`-conditioned ternary was never
avoidable with a "smarter" condition — `var.*` is the only kind of condition
this field supports at all.

## What actually ships: `NOMAD_VAR_deployment_platform` via `set-cluster-env.sh`

Given the condition must be `var.*`, the only way to remove the "forgot the
flag" risk is to make sure the right `var.*` value is supplied automatically
by *something* other than a human typing `-var` — and Nomad's CLI already
has a mechanism for exactly this: it reads `NOMAD_VAR_<name>` environment
variables the same way it reads `-var <name>=value`.

This repo already generates and asks users to `source
ansible/set-cluster-env.sh` after every deploy (for `CONSUL_HTTP_ADDR`,
`NOMAD_TOKEN`, etc.) — a **static, hand-written bash script**, not
Ansible-templated, that parses `ansible/inventory.ini` directly at
source-time. Added a new block to it:

```bash
if grep -q '^consul_use_aws_cloud_join=false' "${_INVENTORY}"; then
    export NOMAD_VAR_deployment_platform="generic"
else
    export NOMAD_VAR_deployment_platform="aws"
fi
```

Reuses the exact same detection signal Ansible's own playbooks already rely
on (`consul_use_aws_cloud_join`, present and `false` only in the
Multipass-generated inventory) — no new marker file, no Ansible role
changes, no `cluster_summary.yaml` changes. `unset-cluster-env.sh` updated
to match (`unset NOMAD_VAR_deployment_platform`).

The job-spec side: renamed the variable from the countdash-specific
`countdash-web-platform` to a single shared `deployment_platform`, used
identically across all three affected job specs — one exported env var
covers all of them, no per-app variable naming or per-app export lines
needed:

```hcl
variable "deployment_platform" {
  default = "generic"
}
...
address = var.deployment_platform == "aws" ? attr.unique.platform.aws.public-hostname : attr.unique.network.ip-address
```

## Scope: which job specs needed this

Audited every job spec for the same class of issue (an externally-facing
service using the platform-agnostic `attr.unique.network.ip-address`, which
loses AWS's public hostname):

| File | Group | Change |
|---|---|---|
| `nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl` | `countdash-web` | Renamed `countdash-web-platform` → `deployment_platform` |
| `nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl` | `countdash-web` | Same rename |
| `nomad-jobs/consul-sd/hashicups-multipass.nomad.hcl` | `nginx` (the only externally-facing group of six) | New — didn't have any fallback before; added `deployment_platform` variable and the same ternary |
| `nomad-jobs/consul-mesh/countdash-upstreams.nomad.hcl` | n/a | Not applicable — bridge networking + Consul Connect sidecars, no explicit `service.address` field at all |

## Verification

All three affected job specs deployed live against the real AWS cluster,
**with zero `-var` flags**, relying purely on
`source ansible/set-cluster-env.sh`:

```
$ source ansible/set-cluster-env.sh
  ...
  NOMAD_VAR_deployment_platform=aws
$ nomad job run nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl
$ curl .../v1/catalog/service/countdash-web?passing | jq -r '.[0].ServiceAddress'
ec2-3-141-30-73.us-east-2.compute.amazonaws.com

$ nomad job run nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl
$ nomad service info countdash-web
...  ec2-3-145-38-9.us-east-2.compute.amazonaws.com:9002  ...

$ nomad job run nomad-jobs/consul-sd/hashicups-multipass.nomad.hcl
$ curl .../v1/catalog/service/nginx?passing | jq -r '.[0].ServiceAddress'
ec2-3-145-38-9.us-east-2.compute.amazonaws.com
```

All three: real, resolved EC2 public DNS hostnames, registered automatically,
no manual flag. The `deployment_platform` variable and its `-var` escape
hatch are both still present in every job spec (for anyone who wants to
override without touching their shell environment), but the documented,
recommended path no longer requires either.

## Related

- [countdash-aws-public-address-fallback.md](countdash-aws-public-address-fallback.md) —
  the original manual-`-var` version of this fix; still accurate for *why*
  the ternary mechanism itself works the way it does (parse-time vs.
  runtime resolution of the ternary's *branches*), superseded only in *how*
  the variable's value gets supplied.
- `nomad-jobs/consul-sd/README-countdash-consul-service-discovery.md` ("How
  traffic flows" section) and
  `nomad-jobs/consul-sd/README-hashicups-multipass.md` ("Traffic flow"
  section) — the user-facing documentation of this mechanism. (Both
  countdash job specs and both HashiCups job specs now live together in
  `nomad-jobs/consul-sd/`, one job-specific README each — see
  `nomad-jobs/consul-sd/README.md` for the index.)
- `ansible/set-cluster-env.sh` / `ansible/unset-cluster-env.sh` — the actual
  detection implementation.
