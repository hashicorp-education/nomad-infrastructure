# Countdash: recovering the AWS public address after the Multipass fix (2026-07-21)

**Update (2026-07-21, later same day)**: the AWS success path noted below as
unverified has now been confirmed against a real AWS cluster — see the
"AWS confirmation" addition under Verification summary.

Follow-on to [countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md)
and [countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md).
Those fixes replaced `attr.unique.platform.aws.public-hostname` with
`attr.unique.network.ip-address` for `countdash-web`'s service registration
so the job runs on Multipass. That traded away something real for AWS
deployments: `attr.unique.network.ip-address` resolves to the EC2 instance's
**private** IP, so the service catalog no longer surfaces an
externally-reachable address for `countdash-web` on AWS. Implemented two
independent ways to recover it.

## Option A: new Terraform outputs, keyed by Nomad node name

`terraform/aws/outputs.tf` already had `server_public_ips` /
`client_public_ips` (plain lists) and the matching `*_private_ips` lists —
usable, but require cross-referencing a private IP (e.g. from `nomad node
status`) against the list by array index to find the corresponding public
IP.

Added `server_public_ips_by_node` / `client_public_ips_by_node`: the same
data, as a map keyed by `"nomad-server-${idx+1}"` / `"nomad-client-${idx+1}"`
— i.e., keyed by the exact node name Ansible assigns and that `nomad node
status` / `nomad job status` already display. No index math needed; look up
the node name directly.

```hcl
output "client_public_ips_by_node" {
  value = {
    for idx, instance in aws_instance.clients :
    "nomad-client-${idx + 1}" => instance.public_ip
  }
}
```

`terraform validate` confirmed clean. Not deployable/testable further here —
this environment has no AWS infrastructure, only the Multipass cluster.

## Option B: job-spec variable to select the AWS attribute — with a real caveat found by testing

Added a `countdash-web-platform` variable (default `"generic"`) to both
`countdash-consul-service-discovery.nomad.hcl` and
`countdash-nomad-service-discovery.nomad.hcl`, and changed `countdash-web`'s
`service.address` to a ternary:

```hcl
address = var.countdash-web-platform == "aws" ? attr.unique.platform.aws.public-hostname : attr.unique.network.ip-address
```

Run with `-var="countdash-web-platform=aws"` on AWS to register the public
hostname instead of the private IP.

### Initial (wrong) assumption, corrected by live testing

First assumption: since `var.*` is known at job-submission/parse time (a
`-var` flag or default, resolved before any node is chosen) while `attr.*`
resolves later per-node, the ternary's *unselected* branch would never
actually be evaluated against a real node's attributes — making it safe to
reference `attr.unique.platform.aws.public-hostname` even when running
against non-AWS infrastructure, since that branch would supposedly never be
reached.

Seemingly confirmed by a first test: `nomad job validate` passed for both
`countdash-web-platform` values, and running with the default (`"generic"`)
value produced **no new job version** (`nomad job history -p
countdash-consul-sd` still showed only version 0) — apparently meaning
Nomad's parser had collapsed the ternary to a single static value before
submission, identical to what was already registered.

**This was wrong.** Tested the actual `"aws"` branch live, on this
Multipass cluster (arm64, confirmed via `nomad node status -verbose` to have
*no* `attr.unique.platform.aws.*` attributes fingerprinted at all — not
empty, absent):

```bash
nomad job run -var="countdash-web-platform=aws" countdash-consul-service-discovery.nomad.hcl
```

Result: the deployment did not error, but `countdash-web` never went
healthy. Querying Consul's catalog directly showed why:

```
"ServiceAddress": "${attr.unique.platform.aws.public-hostname}"
```

The **literal, unresolved template text** — not a real value, not an empty
string, not an error. The health check then failed trying to parse that
literal text as a URL:

```
parse "http://$%7Battr.unique.platform.aws.public-hostname%7D:9002/": invalid URL escape "%7B"
```

Re-deploying with the default (`"generic"`) value afterward correctly
resolved to a real IP (confirmed via the same catalog query) and the
deployment went healthy again — and *that* run also produced a new job
version this time (contradicting the earlier "no new version" observation),
confirming the first test's apparent evidence was coincidental, not proof of
parse-time short-circuiting.

**Actual mechanism** (best understanding after this testing): `service.address`
ternaries ARE resolved per-node, at runtime, like any other `attr.*`
reference — there is no parse-time elision of the unselected branch. When
the selected branch's attribute key doesn't exist on the node performing
the resolution, Nomad doesn't fail cleanly or substitute a default — it
leaves the raw interpolation token as literal text, which then breaks
downstream (URL parsing, health checks) with a confusing, indirect error
rather than a clear "attribute not found."

### Decision: keep it, document the failure signature prominently

Discussed the tradeoff directly: this is a real footgun (wrong or missing
`-var` on the actual platform silently breaks the health check with no
obvious error pointing at the cause) vs. dropping it and relying on Option A
only. Decided to **keep Option B** but document the exact failure signature
prominently in both job specs (large `CAUTION` comment directly above the
ternary) and in `nomad-jobs/consul-sd/README.md`, naming the literal string
(`${attr.unique.platform.aws.public-hostname}`) and error text (`invalid URL
escape "%7B"`) to look for, and explicitly recommending Option A as the
safer default for anyone not certain every deploy will consistently pass the
matching `-var`.

## Verification summary

- `terraform validate` in `terraform/aws/` — clean (new outputs only,
  no AWS credentials needed for this check).
- `nomad job validate` — both job specs, both `countdash-web-platform`
  values — clean.
- Live-deployed on the Multipass cluster with the default (`"generic"`)
  value on both job specs — `countdash-web` healthy, real IP registered in
  Consul.
- Live-deployed `countdash-consul-service-discovery.nomad.hcl` with
  `countdash-web-platform=aws` on the same (non-AWS) cluster specifically
  *to* trigger and document the failure mode above — confirmed, then
  reverted back to the default and re-confirmed healthy.
- **AWS confirmation (2026-07-21, later same day)**: the Multipass cluster
  was destroyed and a real AWS cluster stood up (`terraform apply` in
  `terraform/aws/`) specifically to test what couldn't be verified above.
  Both open questions from this page are now settled:
  - Deployed `countdash-consul-service-discovery.nomad.hcl` with
    `-var="countdash-web-platform=aws"` against the real AWS cluster.
    Queried the Consul catalog directly and confirmed `ServiceAddress` was
    `ec2-3-141-30-73.us-east-2.compute.amazonaws.com` — a real, resolved EC2
    public DNS hostname, not the literal unresolved text seen when this same
    branch was tested (deliberately) against non-AWS infrastructure. `curl`
    to `http://<that-hostname>:9002/` returned `200`. The AWS branch of the
    ternary genuinely works when the target node actually has the
    `attr.unique.platform.aws.public-hostname` attribute.
  - Also confirmed the other previously-arm64-only-tested half of the
    multi-arch fix ([countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md)):
    `hashicorpdev/counter-api:v3-amd64` / `counter-dashboard:v3-amd64`
    correctly pulled and ran on the real amd64 EC2 client node (`docker ps`
    confirmed the exact image tags in use).
  - Also confirmed Option A end-to-end on the real cluster first, before
    testing Option B: `terraform output client_public_ips_by_node` correctly
    mapped a private IP seen in the Consul catalog (`10.0.1.41`, from the
    default/`generic` deploy) to its matching public IP
    (`3.141.30.73`/`nomad-client-1`), reachable directly.

## Related

- [countdash-multipass-multiarch-fix.md](countdash-multipass-multiarch-fix.md)
- [countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md)
- `nomad-jobs/consul-sd/README.md` — "How traffic flows" section has the
  full user-facing writeup of both options and the caution. **Path note**:
  this file (and `countdash-consul-service-discovery.nomad.hcl` itself) lived
  at `nomad-jobs/countdash/` when this page and its two "Related" siblings
  above were originally written; the directory was later split into
  `nomad-jobs/consul-sd/`, `nomad-jobs/nomad-sd/`, and merged into
  `nomad-jobs/consul-mesh/` (one file per scenario, matching the
  `countdash-consul-sd`/`countdash-nomad-sd` job-ID rename from
  [countdash-job-id-collision-and-multiarch.md](countdash-job-id-collision-and-multiarch.md)).
  Older path references in this page's history predate that move.
