# Countdash on Multipass: AWS node attributes + multi-arch images (2026-07-21)

`nomad-jobs/countdash/countdash-consul-service-discovery.nomad.hcl` was written
for the AWS scenarios and had two latent problems that only surface when
deployed to the local Multipass cluster (`terraform/multipass/`). Both are now
fixed and verified with a live deploy. Neither was caught by `nomad job
validate` — both are runtime/placement failures, not schema errors.

## 1. AWS-only node attributes in `service.address`

Both `service` blocks used AWS EC2-metadata-only attributes:

```hcl
# countdash-api
address = attr.unique.platform.aws.local-ipv4

# countdash-web
address = attr.unique.platform.aws.public-hostname
```

These only fingerprint via the EC2 metadata service — absent on Multipass VMs.
This is the exact same class of bug already documented and fixed in
`hashicups-multipass.nomad.hcl` (see that file's header comment), just not yet
carried over to the Countdash job specs.

**Fix**: both replaced with `attr.unique.network.ip-address`, the
platform-agnostic node attribute Nomad fingerprints on every host (AWS,
Multipass, bare metal). Multipass has no public/private network split — one
NIC on the shared bridge network — so the same attribute serves both the
internal (`countdash-api`) and externally-reachable (`countdash-web`) address
roles that AWS needed two different attributes for.

## 2. `hashicorpdev/counter-api:v3` / `counter-dashboard:v3` are amd64-only

Checked via `docker buildx imagetools inspect` and `docker inspect
--format '{{.Architecture}}'`: both tags are single-platform
(`application/vnd.docker.distribution.manifest.v2+json`, not a manifest
list), built for `amd64` only. On the arm64 Multipass VMs (Apple Silicon),
this image does not run natively.

Checked Docker Hub directly — HashiCorp already publishes what's needed:

```
$ curl -s "https://hub.docker.com/v2/repositories/hashicorpdev/counter-api/tags?page_size=100" | ...
v3-amd64  ['amd64']
v3-arm64  ['arm64']
```

Same for `hashicorpdev/counter-dashboard`.

### Can the job spec auto-select by hardware?

Yes — confirmed **empirically** (the official docs are ambiguous/silent on
whether the Docker driver's `image` field supports node-attribute
interpolation; `runtime-variable-interpolation` explicitly calls out
`labels` as a supported Docker field but doesn't mention `image`, and the
Docker task-driver page only confirms `args`). Rather than trust incomplete
docs, ran a throwaway batch job with
`image = "busybox:${attr.cpu.arch}-doesnotexist"` and read the resulting
`Driver Failure` event:

```
Failed to pull `busybox:arm64-doesnotexist`: ... not found
```

The literal `arm64` in the error (not `${attr.cpu.arch}`) proves Nomad's
Docker driver does interpolate `${attr.cpu.arch}` in `image`, resolved
**after** scheduling, on the client that actually got the allocation.

**Important timing distinction**: `var.*` resolves at parse time (`nomad job
run`, before any node is chosen); `${attr.cpu.arch}` resolves later, at
task-start on the client. They can't be combined in an HCL ternary
(`attr.cpu.arch == "amd64" ? var.x : var.y` doesn't work — `attr.cpu.arch`
isn't a value HCL knows about at parse time). But the two substitution passes
*can* be combined in a single string, since they happen independently:

```hcl
variable "countdash-api-version" {
  default = "v3"
}

config {
  image = "hashicorpdev/counter-api:${var.countdash-api-version}-${attr.cpu.arch}"
}
```

`var.countdash-api-version` → `v3` at parse time, leaving
`hashicorpdev/counter-api:v3-${attr.cpu.arch}` in the submitted job; the
client then resolves `${attr.cpu.arch}` → `arm64`/`amd64` once it knows the
node. This only works because HashiCorp's tag naming (`v3-amd64`/`v3-arm64`)
happens to match `attr.cpu.arch`'s own string values exactly — if a project's
image tags don't follow that convention, the alternative is two constrained
task groups (one per arch, each with its own literal image + a `constraint`
on `attr.cpu.arch`), since there's no `locals {}` in Nomad job spec HCL2 to
fall back on for a table-lookup approach.

Applied the same pattern to both tasks (`countdash-api-version` /
`countdash-web-version` variables, both defaulting to `v3`).

## Verification

Both fixes applied together, then deployed live against the real Multipass
cluster:

```
$ nomad job run countdash-consul-service-discovery.nomad.hcl
...
Status = successful
countdash-api  Desired 1  Placed 1  Healthy 1
countdash-web  Desired 1  Placed 1  Healthy 1

$ docker ps --format "{{.Image}} {{.Names}}" | grep countdash
hashicorpdev/counter-api:v3-arm64       countdash-api-...
hashicorpdev/counter-dashboard:v3-arm64 countdash-web-...

$ curl -s -o /dev/null -w "%{http_code}\n" http://<client-ip>:9002/
200
```

Job left running (not stopped/purged) at the user's request.

## Related

- [multipass-local-testing-plan.md](multipass-local-testing-plan.md) — overall
  Multipass workspace plan; this fix is a job-spec-level follow-on to that
  effort, applied after the cluster itself was already validated working.
- `nomad-jobs/hashicups/hashicups-multipass.nomad.hcl` — the earlier,
  already-fixed instance of the same AWS-attribute portability problem.
