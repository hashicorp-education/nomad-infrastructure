# nginx: "host not found in upstream" at startup (Consul DNS race condition)

## Symptom

The `nginx` group in a multi-group Nomad job fails to start. All other service
groups deploy successfully. The nginx allocation restarts repeatedly. The
`stderr` log contains one or more lines like:

```
[emerg] 1#1: host not found in upstream "frontend.service.dc1.global:3000" in /etc/nginx/conf.d/default.conf:3
nginx: [emerg] host not found in upstream "frontend.service.dc1.global:3000" in /etc/nginx/conf.d/default.conf:3
```

The `stdout` log shows the nginx entrypoint completing successfully before each
crash:

```
/docker-entrypoint.sh: Configuration complete; ready for start up
```

The service name in the error message varies per restart — sometimes
`frontend.service.dc1.global`, sometimes `public-api.service.dc1.global` —
because different upstream services finish registering at different times.

---

## Root cause

**nginx resolves hostnames in `upstream {}` blocks and bare `proxy_pass`
directives at config-parse time (startup), not at request time.**

When nginx starts, it reads its configuration file and immediately does a DNS
lookup for every server listed in every `upstream {}` block, and for every
hostname used directly in a `proxy_pass` directive. If any lookup fails, nginx
treats the configuration as invalid and exits with `[emerg]`.

In a multi-group Nomad job, all groups are scheduled at approximately the same
time. nginx may start and parse its config before the `frontend` or `public-api`
groups have finished starting and registering themselves in the Consul service
catalog. Consul therefore returns NXDOMAIN for those names, nginx considers its
config broken, and exits.

Nomad restarts the nginx allocation in a loop. Each restart attempt may
encounter a different service not yet registered, which is why the error message
varies.

This is not a dnsmasq failure — dnsmasq is correctly forwarding `.global`
queries to Consul. Consul is correctly returning NXDOMAIN because the services
are not registered yet. The problem is that nginx fails-fast on unresolvable
upstreams rather than deferring resolution until the first request.

**Why Countdash does not have this problem:** The Countdash web task stores the
API address in an environment variable (`COUNTING_SERVICE_URL`). The Go
process resolves that DNS name lazily, at the moment it makes the first HTTP
request. nginx applies stricter startup validation.

---

## Fix

Use a `resolver` directive and a **variable** in each `proxy_pass` directive
instead of a literal hostname. When nginx sees a variable in `proxy_pass`, it
defers DNS resolution to request time and uses the configured `resolver` for
those lookups.

Replace this pattern (resolves at startup):

```nginx
upstream frontend_upstream {
    server frontend.service.dc1.global:3000;
}
server {
  location / {
    proxy_pass http://frontend_upstream;
  }
  location /api {
    proxy_pass http://public-api.service.dc1.global:8081;
  }
}
```

With this pattern (resolves per-request):

```nginx
resolver 172.17.0.1 valid=5s ipv6=off;
resolver_timeout 2s;

server {
  location / {
    set $frontend_upstream "frontend.service.dc1.global:3000";
    proxy_pass http://$frontend_upstream;
  }
  location /api {
    set $public_api_upstream "public-api.service.dc1.global:8081";
    proxy_pass http://$public_api_upstream;
  }
}
```

**`resolver 172.17.0.1`** — `172.17.0.1` is the Docker bridge gateway where
dnsmasq listens. This is the same address used in every `dns { servers = ["172.17.0.1"] }`
block in the job spec. nginx uses this resolver for all per-request DNS
lookups.

**`valid=5s`** — nginx caches each resolved IP for 5 seconds. After 5 seconds
it re-resolves, which means nginx picks up new Consul service instances within
5 seconds without a restart.

**`ipv6=off`** — disables IPv6 lookups. The Consul agent and dnsmasq in this
cluster do not serve AAAA records. Disabling IPv6 avoids spurious `AAAA` query
failures that can slow down resolution.

**`resolver_timeout 2s`** — sets the maximum time nginx waits for a DNS
response. The default (30 s) is too long for a request-time lookup in a web
proxy.

### Behaviour after the fix

- nginx starts successfully even when upstream services have not yet registered
  in Consul.
- Requests made before an upstream registers receive a 502 from nginx. Once the
  service registers and its DNS name resolves, subsequent requests succeed. For
  a demo workload, this transient 502 window is acceptable.
- DNS re-resolution every 5 seconds means nginx transparently follows Consul
  catalog changes (new allocations, task restarts) without reloading.

### Caveat: upstream {} load-balancing features are not available

When `proxy_pass` uses a variable, nginx cannot use `upstream {}` features such
as weighted round-robin, least-connections, or keepalive connection pooling.
For this demo workload that is not a concern. For production use, consider
nginx Plus (which supports `resolve` in `upstream {}` blocks) or a sidecar
proxy such as Envoy via Consul Connect.

---

## Applied fix location

The fix is implemented in the `nginx` task's `template` block inside
[`nomad-jobs/consul-sd/hashicups.nomad.hcl`](../../nomad-jobs/consul-sd/hashicups.nomad.hcl).

---

## Troubleshooting if nginx still fails after the fix

### 1. Verify dnsmasq is listening on the Docker bridge interface of the ingress node

SSH to the ingress (public) client node and check:

```bash
sudo ss -tlnp | grep dnsmasq
```

Expected output includes both addresses:

```
LISTEN  0  32  127.0.0.1:53  ...
LISTEN  0  32  172.17.0.1:53  ...
```

If only `127.0.0.1:53` appears, re-run the dnsmasq playbook:

```bash
ansible-playbook -i inventory.ini playbooks/dnsmasq.yaml
```

Then redeploy the job.

### 2. Verify the upstream services are registered in Consul

```bash
consul catalog services
```

Expected output includes `frontend`, `public-api`, and the other HashiCups
services. If a service is missing, check its allocation status and logs:

```bash
nomad job allocs hashicups
nomad alloc logs <alloc-id> <task-name>
```

### 3. Test DNS resolution from inside the nginx container

```bash
# Get the nginx allocation ID
nomad job allocs hashicups | grep nginx

# Open a shell in the container
nomad alloc exec -task nginx <alloc-id> /bin/sh

# Inside the container:
nslookup frontend.service.dc1.global
nslookup public-api.service.dc1.global
```

Both lookups should return a private IP address. If they return `SERVFAIL` or
time out, dnsmasq is not reachable from the container — check Step 1.

### 4. Inspect the rendered nginx config

```bash
nomad alloc exec -task nginx <alloc-id> cat /etc/nginx/conf.d/default.conf
```

Verify the `resolver` directive is present and the `proxy_pass` directives use
`$variables` rather than literal hostnames.

---

## Troubleshooting: "site can't be reached" after nginx starts successfully

After the resolver fix was applied and all six HashiCups allocations showed
`running`, the public URL still returned a browser timeout. This section
documents the complete diagnostic sequence used to isolate and confirm the
cause.

### Symptom

Browser shows **"This site can't be reached — took too long to respond"** at
`http://<public-ip>/`. All Nomad allocations are in `running` state. No nginx
errors appear in `nomad alloc logs`.

### Step 1 — Verify the correct public IP

The first attempt used an IP with a typo (`3.144.248.8` instead of
`3.144.248.88`). Always get the IP from Nomad rather than typing it manually:

```bash
nomad node status -verbose \
    $(nomad job allocs hashicups | grep nginx | grep -i running | awk '{print $2}') | \
    grep -i public-ipv4
```

Or from the Consul catalog (gives the hostname the nginx service registered):

```bash
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "$CONSUL_HTTP_ADDR/v1/catalog/service/nginx?passing" \
  | jq -r '.[0].ServiceAddress'
```

### Step 2 — Confirm the security group has port 80 open

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=nomad-consul-sg" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`80`]'
```

The rule must show `"CidrIp": "0.0.0.0/0"`. A VPC-scoped CIDR (`10.0.0.0/16`)
blocks internet traffic even though it allows intra-cluster access.

**Result in this session:** Port 80 was open with `0.0.0.0/0`. Security group
was not the cause.

### Step 3 — SSH to the node and check Docker port binding

```bash
ssh -i ansible/ssh_key.pem ubuntu@<public-ip>
sudo ss -tlnp | grep :80
```

**Observed output:**

```
LISTEN 0  4096  10.0.1.190:80  0.0.0.0:*  users:(("docker-proxy",pid=17040,fd=8))
```

Docker bound port 80 to the **private IP** (`10.0.1.190`), not `0.0.0.0`. This
is expected Nomad behaviour — the Docker task driver publishes static ports to
the node's primary IP as Nomad fingerprints it, not to all interfaces.

On AWS this is not a problem because the public IP is a 1:1 NAT managed by
the VPC. Packets destined for `<public-ip>:80` are translated to
`<private-ip>:80` before they reach the instance OS. docker-proxy listening on
the private IP receives them correctly.

### Step 4 — Check whether Docker containers are actually running

The obvious check `docker ps --filter "name=hashicups"` returns **no results**
because Nomad names Docker containers `<task>-<short-alloc-id>`, not
`<job>-<task>`. Run without a filter:

```bash
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

**Observed output (all six containers running):**

```
nginx-4cbf62f1-...    Up 20 minutes   10.0.1.190:80->80/tcp, 10.0.1.190:80->80/udp
db-525faacd-...       Up 20 minutes   10.0.1.190:5432->5432/tcp, ...
product-api-...       Up 20 minutes   10.0.1.190:9090->9090/tcp, ...
frontend-...          Up 20 minutes   10.0.1.190:3000->3000/tcp, ...
payments-api-...      Up 20 minutes   10.0.1.190:8080->8080/tcp, ...
public-api-...        Up 20 minutes   10.0.1.190:8081->8081/tcp, ...
```

Note that all six groups landed on the same node because the job has no node
constraints. This is valid — static ports are all distinct.

### Step 5 — Test nginx from within the host

```bash
curl -sv http://127.0.0.1/health    # connection refused — port not on loopback
curl -sv http://10.0.1.190/health   # HTTP 200 {"status":"UP"}
```

`127.0.0.1` fails because Docker published to `10.0.1.190`, not `0.0.0.0`.
`10.0.1.190` succeeds, confirming nginx is healthy and responding correctly
on the private IP.

### Step 6 — Check host firewall and iptables

```bash
sudo ufw status verbose
```

**Result:** `Status: inactive`. UFW is not the cause.

```bash
sudo iptables -L FORWARD -n -v | head -30
```

**Observed output:**

```
Chain FORWARD (policy DROP 0 packets, 0 bytes)
 pkts bytes target       prot opt in  out  source    destination
  176 169K  DOCKER-USER  0    --  *   *    0.0.0.0/0 0.0.0.0/0
  176 169K  DOCKER-FORWARD 0  --  *   *    0.0.0.0/0 0.0.0.0/0
```

The FORWARD chain has a `DROP` default policy, but all 176 packets matched the
`DOCKER-USER` and `DOCKER-FORWARD` chains (Docker's own rules), so no traffic
was dropped. This is the normal Docker iptables configuration.

```bash
sudo iptables -t nat -L DOCKER -n | grep :80
```

**Observed output (DNAT rules in place):**

```
DNAT  tcp  --  0.0.0.0/0  10.0.1.190  tcp dpt:80    to:172.17.0.7:80
DNAT  udp  --  0.0.0.0/0  10.0.1.190  udp dpt:80    to:172.17.0.7:80
DNAT  tcp  --  0.0.0.0/0  10.0.1.190  tcp dpt:8080  to:172.17.0.4:8080
DNAT  tcp  --  0.0.0.0/0  10.0.1.190  tcp dpt:8081  to:172.17.0.2:8081
```

The DNAT rule for port 80 correctly redirects traffic arriving at
`10.0.1.190:80` to the nginx container at `172.17.0.7:80`. iptables was not
the cause.

### Step 7 — Confirm external TCP connectivity

From the local machine:

```bash
nc -zv 3.144.248.88 80
```

**Result:** `Connection to 3.144.248.88 80 port [tcp/http] succeeded!`

TCP port 80 is reachable from the internet. The connection is not being
blocked at the network level. The issue is therefore at the HTTP layer or in
the browser.

### Step 8 — Test full HTTP from the local machine

```bash
curl -v http://3.144.248.88/health    # HTTP 200 {"status":"UP"}
curl -v http://3.144.248.88/          # HTTP 200 full HashiCups HTML
```

Both returned HTTP 200. **HashiCups is working correctly.** The problem was
entirely in the browser — see the section below.

### Key diagnostic: `docker ps` filter

Nomad Docker container naming follows the pattern `<task>-<short-alloc-id>`.
The job name does not appear. `--filter "name=<job>"` will always return no
results for Nomad-managed containers. Always run `docker ps` without a filter
when investigating Nomad workloads on a node.

---

## Browser behaviour: Brave silently upgrades HTTP to HTTPS

After the nginx fix was applied and the job deployed successfully, `curl
http://<public-ip>/` returned HTTP 200 and the full HashiCups HTML, but Brave
browser showed **"took too long to respond"** for the same URL.

**Root cause:** Brave's built-in **"Upgrade connections to HTTPS"** feature
rewrites `http://` to `https://` for all addresses, including bare IP
addresses, even when the user explicitly types `http://`. Port 443 is not open
and nginx has no TLS configuration, so the HTTPS attempt times out without
producing a meaningful error.

**Confirmation:** `curl -v http://<public-ip>/health` and `curl -v
http://<public-ip>/` both returned HTTP 200 from the same machine where Brave
was timing out. Firefox opened the same URL without issue.

**Fix:** Use Firefox, Chrome, or Safari. Alternatively, disable Brave Shields
for the address or turn off "Upgrade connections to HTTPS" in
`brave://settings/shields`.

This is not a server-side issue. No changes to the Nomad job, nginx
configuration, or security group are required.
