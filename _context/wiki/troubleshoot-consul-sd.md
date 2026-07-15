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
`countdash-api.service.dc1.consul`. The web app then cannot connect to the API.

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
nslookup countdash-api.service.dc1.consul
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

## Related files

- [`nomad-jobs/countdash-consul-service-discovery.nomad.hcl`](../../nomad-jobs/countdash-consul-service-discovery.nomad.hcl)
- [`ansible/roles/dnsmasq/README.md`](../../ansible/roles/dnsmasq/README.md) — dnsmasq OS interaction and Docker bridge DNS details
- [`_context/wiki/dnsmasq-consul-docker-dns.md`](dnsmasq-consul-docker-dns.md) — root cause analysis of the `dnsmasq_listen_addresses` fix
