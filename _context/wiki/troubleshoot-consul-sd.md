# Troubleshooting: "Counting service is unreachable" (Consul service discovery)

## Symptom

The Countdash web UI loads at `http://<public-hostname>:9002/` but displays
**"Counting service is unreachable"**. The Nomad job deployed without error and
both `countdash-web` and `countdash-api` are registered in Consul.

## Root cause summary

The web container sets `dns { servers = ["172.17.0.1"] }` so Docker routes its
DNS queries to the host via the bridge gateway. If dnsmasq is only listening on
`127.0.0.1` (the default before the `dnsmasq_listen_addresses` fix), nothing
answers on `172.17.0.1:53` and the container cannot resolve
`countdash-api.service.dc1.global`. The web app then cannot connect to the API.

Three possible failure layers, in order of likelihood:

| Layer | Symptom | Fix |
|-------|---------|-----|
| dnsmasq not listening on Docker bridge | DNS queries from container silently dropped | Re-run dnsmasq playbook with `dnsmasq_listen_addresses` list |
| DNS resolves but TCP connection refused | `nslookup` succeeds, `wget` times out | Check cross-node `self` security group rule; check API task is running |
| API process not ready | TCP connects but health check fails | Wait for JVM warm-up; check `nomad alloc logs` |

---

## Step 1 — Verify dnsmasq is listening on the Docker bridge interface

SSH to the Nomad client node running the `countdash-web` task:

```bash
sudo ss -tlnp | grep dnsmasq
```

Expected output after the fix:

```
LISTEN  0  32  127.0.0.1:53  ...  dnsmasq
LISTEN  0  32  172.17.0.1:53  ...  dnsmasq
```

If only `127.0.0.1:53` appears, dnsmasq was deployed before the
`dnsmasq_listen_addresses` list was added to `group_vars/all.yaml`. Re-run the
dnsmasq playbook from the `ansible/` directory:

```bash
ansible-playbook -i inventory.ini playbooks/dnsmasq.yaml
```

After the playbook completes, verify both addresses appear, then redeploy the job
so the containers pick up a fresh DNS configuration:

```bash
nomad job stop countdash
nomad job run nomad-jobs/countdash-consul-service-discovery.nomad.hcl
```

---

## Step 2 — Test DNS resolution from inside the web container

Get the allocation ID for the `countdash-web` task:

```bash
nomad job status countdash
nomad alloc exec -task countdash-web <alloc-id> /bin/sh
```

Inside the container, check the resolver and resolve the API service name:

```bash
# Should show: nameserver 172.17.0.1
cat /etc/resolv.conf

# Should return the private IP of the client node running the API
nslookup countdash-api.service.dc1.global
```

If `nslookup` returns `SERVFAIL` or times out, DNS is still broken — go back to
Step 1. If it returns an IP address, proceed to Step 3.

---

## Step 3 — Test direct HTTP connectivity to the API

Still inside the web container, connect to the API's health endpoint using the
IP from Step 2:

```bash
wget -qO- http://<resolved-ip>:9001/actuator/health
```

Expected response: `{"status":"UP"}`

If the connection times out or is refused, the issue is network connectivity
rather than DNS. Check which client node each task landed on:

```bash
nomad alloc status <web-alloc-id>   # shows which node
nomad alloc status <api-alloc-id>   # shows which node
```

If the tasks are on different nodes, port `9001` must be reachable between them.
The `self = true` security group rule in `terraform/aws/network.tf` allows all
traffic between instances that share the security group. Verify it is in place:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=nomad-consul-sg" \
  --query 'SecurityGroups[0].IpPermissions[?IpProtocol==`-1`]'
```

---

## Step 4 — Verify the Consul health check is passing for the API

From your local terminal (with `CONSUL_HTTP_ADDR` and `CONSUL_HTTP_TOKEN` set):

```bash
# Empty result means no healthy instances — health check is failing
curl -s -H "X-Consul-Token: $CONSUL_HTTP_TOKEN" \
  "$CONSUL_HTTP_ADDR/v1/health/service/countdash-api?passing" \
  | jq '.[].Service | {Address, Port}'
```

If the result is empty, the API health check (`GET /actuator/health`) is
failing. This is common on first deployment because the JVM takes 30–60 seconds
to become ready. Check the allocation logs:

```bash
nomad alloc logs <api-alloc-id> countdash-api
```

The `check_restart { limit = 0 }` block in the job spec prevents Nomad from
restarting the task on health failure, so the API will become healthy on its own
once the JVM finishes starting.

---

## Step 5 — SERVFAIL from Consul DNS (stale token file)

### Symptom

After running `consul_dns_token.yaml` and confirming the consul.hcl on each
client contains `acl.tokens.dns = "<uuid>"`, `dig @127.0.0.1 -p 8600` still
returns `status: SERVFAIL` with the `aa` (authoritative) flag set. Running
`consul acl token list` shows no `dns-access` policy and no DNS token matching
the UUID in the config file.

### Root cause

`consul_dns_token.yaml` uses `ansible/tokens/consul-dns-secret-id.txt` as an
idempotency sentinel: if the file exists, token creation is skipped. When a
cluster is destroyed and rebuilt without running `teardown.yaml`, the stale
token file from the previous cluster persists. The playbook skips token
creation, and Play 3 writes the old UUID into the new `consul.hcl`. Consul
does not recognise the ghost token, returns a 403 for every DNS lookup, and
DNS reports SERVFAIL.

### Diagnostic confirmation

```bash
# The DNS token UUID from consul.hcl should appear here — if it does not, the
# token was never created for this cluster
export CONSUL_HTTP_TOKEN=$(cat ansible/tokens/consul-bootstrap-secret-id.txt)
export CONSUL_HTTP_ADDR=http://<server-public-ip>:8500
consul acl token list

# Also confirm no dns-access policy exists
consul acl policy list
```

If `dns-access` is absent and the UUID in `consul.hcl` does not appear in
`consul acl token list`, the stale file is the cause.

### Fix

```bash
cd ansible
rm tokens/consul-dns-secret-id.txt
ansible-playbook -i inventory.ini playbooks/consul_dns_token.yaml
```

After the playbook completes, verify DNS from the client:

```bash
dig @127.0.0.1 -p 8600 countdash-api.service.dc1.global
# Expected: status: NOERROR with an A record
```

Then restart the Nomad job to refresh the `COUNTING_SERVICE_URL` env var:

```bash
nomad job stop countdash
nomad job run nomad-jobs/countdash-consul-service-discovery.nomad.hcl
```

### Prevention

Always run `teardown.yaml` before `terraform destroy` — it removes token files
along with the cluster software. If you skip teardown (for example, running
`terraform destroy` directly), manually delete all files under `ansible/tokens/`
before running the next deployment.

---

## Related files

- [`nomad-jobs/countdash-consul-service-discovery.nomad.hcl`](../../nomad-jobs/countdash-consul-service-discovery.nomad.hcl)
- [`ansible/roles/dnsmasq/README.md`](../../ansible/roles/dnsmasq/README.md) — dnsmasq OS interaction and Docker bridge DNS details
- [`_context/wiki/dnsmasq-consul-docker-dns.md`](dnsmasq-consul-docker-dns.md) — root cause analysis of the `dnsmasq_listen_addresses` fix
