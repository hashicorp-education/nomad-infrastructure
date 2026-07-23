# Review: `devmode-macos/nomad.md` and `devmode-macos/consul.md`

## Scope

`devmode-macos/nomad.md` and `devmode-macos/consul.md` are new standalone
guides (not tied to this repo's Terraform/Ansible cluster) covering
`nomad agent -dev` / `consul agent -dev` on a bare macOS machine — install,
Docker Desktop config, dev-flag semantics, example jobs, and two Countdash
variants (`nomad-jobs/nomad-sd/` and `nomad-jobs/consul-sd/`, both of which
*are* this repo's job specs).

Reviewed for accuracy against the actual source, not just the docs site:
`/Users/aimeeu/Dev/github/hashicorp/nomad` (`command/agent/config.go`,
`drivers/docker/driver.go`, `jobspec2/types.variables.go`) and
`/Users/aimeeu/Dev/github/hashicorp/consul` (`agent/config/default.go`,
`agent/config/builder.go`, `agent/sidecar_service.go`), plus
[`nomad agent`](https://developer.hashicorp.com/nomad/commands/agent) and
[`consul agent`](https://developer.hashicorp.com/consul/commands/agent).

Most of the source-level claims held up exactly as written — see
[What checked out](#what-checked-out) below. Three did not, and all three are
now fixed in the guides.

---

## Finding 1 — Section 10's Consul command is missing `-domain=global`, breaking the guide's own walkthrough

### Symptom (as originally written)

`nomad.md` §10 ("Countdash: Consul service discovery") told the reader to
start Consul with:

```bash
consul agent -dev -client=0.0.0.0
```

then deploy `countdash-consul-service-discovery.nomad.hcl`. Following those
steps to the letter, the "Verify DNS resolution" step's

```bash
nslookup countdash-api.service.dc1.global 172.17.0.1
```

returns NXDOMAIN, and the dashboard shows a connection error instead of a
count.

### Root cause

`countdash-consul-service-discovery.nomad.hcl` hardcodes
`countdash-api.service.dc1.global` as the API URL:

```hcl
env {
  COUNTING_SERVICE_URL = "http://countdash-api.service.dc1.global:${var.countdash-api-port}"
}
```

The `.global` suffix is **this repo's own convention**, not a Consul default —
`ansible/group_vars/all.yaml`:

```yaml
# Consul DNS domain — all service DNS names end with .<domain>.
# The default Consul domain is "consul"; this project uses "global" to avoid
# conflicts with the ICANN-registered .consul TLD ...
consul_domain: "global"
```

Consul's actual dev-mode default domain is `consul.`
(`agent/config/default.go:46`, `domain = "consul."`) — confirmed it is not
overridden anywhere in `DevSource()`. A vanilla `consul agent -dev` only
answers DNS queries on `*.consul`, never `*.global`, so the job's hardcoded
`.global` hostname can never resolve unless the agent is explicitly told to
use that domain.

### Fix applied

`nomad.md` §10's Prerequisites table now reads:

```bash
consul agent -dev -client=0.0.0.0 -domain=global
```

with a callout explaining why, and a new troubleshooting-table row
cross-referencing it.

---

## Finding 2 — `NOMAD_VAR_countdash_api_port` env-var override example silently does nothing

### Symptom (as originally written)

`nomad.md` §9 ("Override defaults") offered this as an alternative to
`-var`:

```bash
export NOMAD_VAR_countdash_api_port=19001
export NOMAD_VAR_countdash_web_port=19002
nomad job run countdash-nomad-service-discovery.nomad.hcl
```

Run as written, the job deploys with the **default** ports (9001/9002), not
19001/19002 — with no error or warning.

### Root cause

The job's variables are declared with hyphens:

```hcl
variable "countdash-api-port" { default = 9001 }
variable "countdash-web-port" { default = 9002 }
```

Nomad's `NOMAD_VAR_<name>` parser
(`jobspec2/types.variables.go:collectInputVariableValues`) does an exact
string match on the name after the prefix:

```go
name := raw[:eq]
variable, found := variables[name]
if !found {
    // this variable was not defined in the hcl files, let's skip it !
    continue
}
```

There is no hyphen/underscore normalization. And POSIX shells cannot export
an environment variable whose name contains a hyphen (`export
NOMAD_VAR_countdash-api-port=...` is a shell syntax error) — so there is no
spelling of `NOMAD_VAR_...` that can ever match a variable named
`countdash-api-port`. The mismatch is silent: `found` is `false`, the loop
just `continue`s, and `nomad job run` proceeds with the variable's default
value as if no override were given.

### Fix applied

Replaced the broken example in §9 with an explanation of the constraint and
a pointer back to `-var`, which has no such restriction (Nomad's `-var` flag
parsing is a plain `key=value` split, not filtered through a shell
identifier).

---

## Finding 3 — `consul.md` ports table mislabels `20000–20255` as "Envoy xDS proxy range"

### What was wrong

The Ports and URLs table listed:

| Service | Port |
|---|---|
| Envoy xDS proxy range | `20000`–`20255` |

### Root cause

`20000–20255` is `ports.proxy_min_port` / `ports.proxy_max_port`
(`agent/config/default.go:133-134`). Grepping the Consul source
(`ProxyMinPort`/`ProxyMaxPort`) shows these values are read out of config in
`agent/config/builder.go` and `sdk/testutil/server.go` and **never consumed
anywhere else** — they're a leftover from Consul's old "managed proxy"
feature (removed years ago) and do nothing functionally in a modern Connect
deployment. Actual Envoy xDS traffic goes over the gRPC port (`8502`),
already listed as its own correctly-labeled row two lines above. The
sidecar port range immediately below (`21000–21255`,
`ConnectSidecarMinPort`/`MaxPort`) *is* live — consumed in
`agent/sidecar_service.go` — so that row was accurate as written.

### Fix applied

Relabeled the row `proxy_min_port`–`proxy_max_port` and corrected the
description to note it's vestigial and not used by modern Envoy/Connect.

---

## What checked out

Verified accurate against source, no changes needed:

- `-dev` / `-dev-consul` / `-dev-connect` / `-dev-vault` defaults in
  `command/agent/config.go:DevConfig()` — bind address, log level,
  `driver.raw_exec.enable`, `driver.docker.volumes`, GC thresholds (99%),
  Nomad service discovery, Prometheus metrics, workload identity
  audiences/TTLs (`consul.io`/`vault.io`, 1h) for both `-dev-consul` and
  `-dev-vault`.
- `-dev-connect`'s Linux-only, root-only, and `consul`-on-`$PATH`
  requirements (`devModeConfig.validate()`), and that it binds `0.0.0.0` on
  the first non-loopback interface (`networkConfig()`).
- Nomad's dynamic port range (20000–32000,
  `nomad/structs/network.go`) and client alloc port range (14000–14512,
  `command/agent/config.go:1849-1850`).
- `nomad service list` / `nomad service info` as real CLI subcommands.
- Docker driver `:latest`-tag pull behavior
  (`drivers/docker/driver.go:createImage` — any tag other than `latest`
  short-circuits to a local `ImageInspect` cache hit; `latest` always calls
  `pullImage`), matching the guide's "local-only `:latest` images fail to
  pull" troubleshooting entry.
- Consul's `DevSource()`/`DevConsulSource()` values in
  `agent/config/default.go` — `bind_addr`, `log_level`, `ports.grpc = 8502`,
  `ui_config.enabled`, `connect.enabled`, `peering.enabled`,
  `performance.raft_multiplier = 1`, gossip timeouts (100ms), raft timeouts
  (52ms/35ms).
- `data_dir` and `bootstrap_expect` dev-mode enforcement in
  `agent/config/builder.go:1244` and `:1357-1358` (exact line numbers, still
  current).
- The two Countdash job specs
  (`nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl`,
  `nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl`)
  against the guide's descriptions of `nomadService` template lookup vs.
  Consul DNS, `shutdown_delay`, and the `172.17.0.1` Docker-bridge DNS
  forwarding — all matched.

---

## Related files

- [`devmode-macos/nomad.md`](../../devmode-macos/nomad.md)
- [`devmode-macos/consul.md`](../../devmode-macos/consul.md)
- [`nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl`](../../nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl)
- [`nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl`](../../nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl)
- [`ansible/group_vars/all.yaml`](../../ansible/group_vars/all.yaml) — source of the `consul_domain: "global"` convention
- [`troubleshoot-consul-sd.md`](troubleshoot-consul-sd.md) — this repo's ansible-deployed cluster hits the same `.global`-domain DNS shape from a different root cause (stale ACL token, not a missing `-domain` flag)
