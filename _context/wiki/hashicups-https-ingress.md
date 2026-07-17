# HashiCups: adding a self-signed HTTPS ingress and removing plain HTTP

## Summary

The HashiCups demo job (`nomad-jobs/hashicups/hashicups.nomad.hcl`) originally
exposed its `nginx` reverse proxy on plain HTTP, port 80, to the internet.
This session added a self-signed HTTPS listener on port 443, then removed the
HTTP listener entirely so end users can only reach HashiCups over HTTPS. Along
the way, a Nomad runtime-variable naming bug (`NOMAD_IP_<port-label>`
sanitization) broke the first deploy attempt.

This is unrelated to the cluster's own Consul/Nomad control-plane TLS (see
[tls-enabled-troublshooting.md](tls-enabled-troublshooting.md)) — it is
TLS for the *application* nginx serves, configured entirely inside the Nomad
job spec.

---

## Design: self-signed cert generated at deploy time, no external CA

Rather than pre-generating a certificate with Ansible (as the cluster's own
`tls` role does for Consul/Nomad), HashiCups generates its certificate
**inside the Nomad job itself**, using a `prestart` lifecycle task:

```hcl
task "nginx-tls-init" {
  driver = "docker"

  lifecycle {
    hook    = "prestart"
    sidecar = false
  }

  config {
    image   = "nginx:alpine"
    command = "sh"
    args = [
      "-c",
      <<-EOT
      set -e
      apk add --no-cache openssl
      mkdir -p /alloc/tls
      openssl req -x509 -nodes -newkey rsa:2048 \
        -keyout /alloc/tls/nginx.key \
        -out /alloc/tls/nginx.crt \
        -days 365 \
        -subj "/CN=hashicups.local" \
        -addext "subjectAltName=DNS:hashicups.local,IP:${NOMAD_IP_nginx_tls}"
      EOT
    ]
  }
}
```

Why this approach:

- **No external dependency.** Reuses the same `nginx:alpine` image already
  being pulled for the main task — no extra image, no Ansible role, no
  cluster-wide CA involvement.
- **Dynamic SAN.** The cert's Subject Alternative Name is generated from
  `NOMAD_IP_nginx_tls` at deploy time, so it matches whichever client node the
  scheduler places the allocation on — no hardcoded IP list to maintain.
- **Shared via `/alloc`.** Nomad automatically mounts the allocation directory
  (`/alloc`) into every task in a group. The `nginx-tls-init` task writes the
  cert/key there; the `nginx` task reads them from the same path with no
  explicit `mount` or `volume` stanza needed.
- **`prestart` + `sidecar = false`** guarantees `nginx-tls-init` runs to
  completion (cert exists on disk) before the `nginx` task starts, and doesn't
  linger as a running process afterward.

The `nginx` task's templated `default.conf` then adds:

```nginx
server {
  listen 443 ssl;
  server_name {{ env "NOMAD_IP_nginx_tls" }};
  ssl_certificate     /alloc/tls/nginx.crt;
  ssl_certificate_key /alloc/tls/nginx.key;
  ...
}
```

---

## Bug: `NOMAD_IP_nginx` vs `NOMAD_IP_nginx_tls`

### Symptom

After renaming the job's network `port` label from `nginx` (plain HTTP, being
removed) to keeping only `nginx-tls` (443), the first redeploy attempt put the
`nginx` group into a restart loop:

```
nomad job status hashicups
...
Task Group   Queued  Starting  Running  Failed  Complete  Lost  Unknown
nginx        0       0         0        2       2         0     0
```

`nomad alloc status <id>` showed the `nginx-tls-init` prestart task dying
immediately with:

```
Failed Validation  2 errors occurred:
        * failed to parse config:
        * Unknown variable: There is no variable named "NOMAD_IP_nginx".
```

### Root cause

Nomad exposes each `network { port "<label>" {...} }` block's assigned address
as an env var named `NOMAD_IP_<label>` — but **it sanitizes the label first,
replacing any character that isn't valid in a shell env var name (including
`-`) with `_`**. The port label in this job is `nginx-tls`, so the actual
runtime variable is `NOMAD_IP_nginx_tls`, not `NOMAD_IP_nginx`.

The job's `nginx-tls-init` task args and the `nginx` template's `server_name`
directive were both still referencing the old `NOMAD_IP_nginx` name (a
leftover from when the port label used to be `nginx`, before it was renamed to
`nginx-tls`). Because `${NOMAD_IP_nginx}` no longer resolved to anything,
Nomad's interpolation step failed validation and the task never started.

### Fix

Update both references to match the sanitized label:

```diff
- -addext "subjectAltName=DNS:hashicups.local,IP:${NOMAD_IP_nginx}"
+ -addext "subjectAltName=DNS:hashicups.local,IP:${NOMAD_IP_nginx_tls}"
```

```diff
- server_name {{ env "NOMAD_IP_nginx" }};
+ server_name {{ env "NOMAD_IP_nginx_tls" }};
```

**Lesson learned:** Whenever a Nomad `network { port "<label>" {...} }` label
is renamed, grep the whole job file for `NOMAD_IP_<old-label>`,
`NOMAD_PORT_<old-label>`, and `NOMAD_ADDR_<old-label>` — Nomad does not warn
at rename time, only at job-run time via a "no variable named ..." validation
error, and the sanitization rule (hyphens become underscores) is easy to
forget when a label itself contains a hyphen.

---

## Closing the plain-HTTP path entirely

After confirming HTTPS worked end-to-end, the decision was made to stop
exposing port 80 altogether (no HTTP fallback for end users):

- **Nomad job:** removed the `port "nginx"` (80) network block, the plain
  `server { listen 80; ... }` block from the nginx config template, the
  `nginx_port` variable, and updated `ports = [...]` in the `nginx` task's
  `config` block to list only `nginx-tls`.
- **Consul health check:** switched from `type = "http"` (implicit HTTP) to:
  ```hcl
  check {
    type            = "http"
    protocol        = "https"
    tls_skip_verify = true
    path            = "/health"
  }
  ```
  `tls_skip_verify = true` is required because the cert is self-signed —
  without it, Consul's own health check would fail cert validation and mark
  the service unhealthy.
- **AWS security group:** removed the port 80 ingress rule. Since
  `terraform/aws/network.tf` declares the security group's `extra_ingress_ports`
  as a single `dynamic "ingress"` block inside one `aws_security_group`
  resource (not per-rule resources), a plain `terraform apply` — after
  removing the `{ port = 80, ... }` entry from `terraform.tfvars` — fully
  reconciled the live rule set and removed port 80, even though the Ansible
  ad-hoc playbook (`update-security-group.yaml`) had been used earlier to open
  it (that playbook only supports *adding* ports, not revoking them).

Verified live post-fix:

```bash
aws ec2 describe-security-groups --group-ids <sg-id> --region us-east-2 \
  --query "SecurityGroups[0].IpPermissions[?ToPort==\`80\` || ToPort==\`443\`]"
```
returned only the port 443 rule.

---

## Related documentation

- [nomad-jobs/hashicups/README.md](../../nomad-jobs/hashicups/README.md) — full job architecture, security group requirements, deploy/verify/clean-up commands
- [tls-enabled-troublshooting.md](tls-enabled-troublshooting.md) — cluster-level (Consul/Nomad control-plane) TLS bugs, a separate concern from this application-level TLS
- [nginx-upstream-dns-startup-failure.md](nginx-upstream-dns-startup-failure.md) — a different nginx startup bug in this same job (DNS resolution timing), unrelated to TLS
