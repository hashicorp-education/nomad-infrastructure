# Consul service mesh — config entries and API Gateway

This directory contains Consul config entries and the Nomad API Gateway job
for the **Option E** service mesh deployment. These files work together with
the mesh-enabled Nomad job specs in
[`../countdash/`](../countdash/) and [`../hashicups/`](../hashicups/).

## Prerequisites

The cluster must already be deployed with Option D (workload identity):

```bash
cd ansible
ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml
source set-cluster-env.sh
```

Then run the mesh-enabling playbook:

```bash
ansible-playbook -i inventory.ini playbooks/consul_nomad_service_mesh.yaml
```

Verify Consul Connect is active on both Nomad clients before continuing:

```bash
nomad node status -verbose \
  $(nomad node status -short | grep ready | awk '{print $1}') \
  | grep consul.connect
# consul.connect = true  (must appear for every client node)
```

Port 8447 must be open in the AWS security group. If you have not already
applied the Terraform change:

```bash
# terraform/aws/terraform.tfvars already contains port 8447 — just apply:
cd terraform/aws
terraform plan
terraform apply
```

## Deploy order

Follow this order exactly. Each step depends on the previous one.

### 1. Apply service-defaults

`service-defaults` config entries tell Consul which protocol each service
speaks. The API Gateway requires `http` on every destination service it routes
to. PostgreSQL must use `tcp`.

```bash
# Countdash (already applied in Step 4 of the rollout, repeated here for completeness)
consul config write service-defaults/countdash-api.hcl
consul config write service-defaults/countdash-web.hcl

# HashiCups
consul config write service-defaults/nginx.hcl
consul config write service-defaults/frontend.hcl
consul config write service-defaults/public-api.hcl
consul config write service-defaults/product-api.hcl
consul config write service-defaults/payments-api.hcl
consul config write service-defaults/database.hcl
```

Verify:

```bash
consul config list -kind service-defaults
```

### 2. Apply service intentions

One `service-intentions` file per **destination** service. Every unlisted
source→destination pair is denied (Consul default-deny ACL policy).

```bash
# Countdash (already applied in Step 5 of the rollout)
consul config write intentions/countdash-api.hcl
consul config write intentions/countdash-web.hcl

# HashiCups
consul config write intentions/nginx.hcl
consul config write intentions/frontend.hcl
consul config write intentions/public-api.hcl
consul config write intentions/product-api.hcl
consul config write intentions/payments-api.hcl
consul config write intentions/database.hcl
```

Verify a specific path:

```bash
consul intention check api-gateway nginx    # Allowed
consul intention check nginx database       # Denied (not in intentions)
```

### 3. Generate the gateway TLS certificate and apply the inline-certificate config entry

The API Gateway terminates HTTPS. It needs a certificate that the browser will
accept (or click through for a self-signed cert). Generate and apply in one
pipeline — never commit cert/key material to the repo:

```bash
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout /tmp/gateway.key \
  -out /tmp/gateway.crt \
  -days 365 \
  -subj "/CN=api-gateway.local" \
  -addext "subjectAltName=IP:<public_ip_of_any_client_node>"

consul config write - <<EOF
Kind        = "inline-certificate"
Name        = "api-gateway-cert"
Certificate = "$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' /tmp/gateway.crt)"
PrivateKey  = "$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' /tmp/gateway.key)"
EOF
```

Verify:

```bash
consul config read -kind inline-certificate -name api-gateway-cert
```

### 4. Apply the api-gateway listener config entry

```bash
consul config write gateway-listener.hcl
```

This registers the `api-gateway` config entry with an HTTPS listener on port
8447 referencing the `api-gateway-cert` inline-certificate.

### 5. Apply http-routes

```bash
consul config write http-route-countdash.hcl
consul config write http-route-hashicups.hcl
```

> **Note:** both routes use `"prefix": "/"`. If you deploy both countdash-mesh
> and hashicups-mesh at the same time, the gateway will route all traffic to
> whichever route was registered last. For isolated testing, apply only one
> route at a time, or add a `Host` header match to distinguish them.

### 6. Store the Consul CA cert as a Nomad variable

The API Gateway job reads the Consul CA cert from a Nomad variable so it can
trust the cluster's self-signed TLS certificate:

```bash
nomad var put -namespace ingress \
  nomad/jobs/api-gateway/gateway/setup \
  consul_cacert=@ansible/.tls/ca.pem
```

Verify:

```bash
nomad var get -namespace ingress nomad/jobs/api-gateway/gateway/setup
```

### 7. Deploy and verify the countdash mesh job

```bash
nomad job run nomad-jobs/countdash/countdash-consul-service-mesh.nomad.hcl
nomad job status countdash-mesh
# Wait until all allocs are "running" with a connect-proxy-* sidecar task
```

Check sidecar logs for bootstrap errors:

```bash
nomad alloc logs -task connect-proxy-countdash-web \
  $(nomad job allocs countdash-mesh | grep countdash-web | grep running | awk '{print $1}')
```

### 8. Deploy the API Gateway job

```bash
nomad job run -namespace ingress nomad-jobs/consul-mesh/api-gateway.nomad.hcl
nomad job status -namespace ingress api-gateway
```

Check gateway task logs:

```bash
nomad alloc logs -namespace ingress -task gateway \
  $(nomad job allocs -namespace ingress api-gateway | grep running | awk '{print $1}')
```

Verify the gateway is reachable (replace `<IP>` with any client node's public IP):

```bash
curl -k https://<IP>:8447/
# Should return the countdash-web UI (HTML response)
```

### 9. Deploy the HashiCups mesh job

```bash
nomad job run nomad-jobs/hashicups/hashicups-consul-service-mesh.nomad.hcl
nomad job status hashicups-mesh
```

Switch the active http-route to hashicups (if countdash route was applied):

```bash
consul config delete -kind http-route -name countdash
consul config write http-route-hashicups.hcl
```

Verify:

```bash
curl -k https://<IP>:8447/
# Should return the HashiCups nginx proxy (HTML response)
```

## Verification checklist

- [ ] `consul config list -kind service-defaults` shows all 8 services
- [ ] `consul config list -kind service-intentions` shows all 8 destinations
- [ ] `consul config list -kind inline-certificate` shows `api-gateway-cert`
- [ ] `consul config list -kind api-gateway` shows `api-gateway`
- [ ] `consul config list -kind http-route` shows active route(s)
- [ ] `nomad var get -namespace ingress nomad/jobs/api-gateway/gateway/setup` returns the CA cert
- [ ] `nomad job status countdash-mesh` — all allocs running with `connect-proxy-*` sidecars
- [ ] `nomad job status -namespace ingress api-gateway` — allocation running
- [ ] `curl -k https://<IP>:8447/` — HTTP 200 response
- [ ] `consul intention check api-gateway countdash-web` — Allowed
- [ ] `consul intention check api-gateway nginx` — Allowed
- [ ] Spot-check a denied path: `consul intention check nginx database` — Denied

## Clean up

```bash
# Stop mesh jobs
nomad job stop -purge -namespace ingress api-gateway
nomad job stop -purge hashicups-mesh
nomad job stop -purge countdash-mesh

# Remove config entries
consul config delete -kind http-route -name countdash
consul config delete -kind http-route -name hashicups
consul config delete -kind api-gateway -name api-gateway
consul config delete -kind inline-certificate -name api-gateway-cert
consul config delete -kind service-intentions -name countdash-api
consul config delete -kind service-intentions -name countdash-web
consul config delete -kind service-intentions -name nginx
consul config delete -kind service-intentions -name frontend
consul config delete -kind service-intentions -name public-api
consul config delete -kind service-intentions -name product-api
consul config delete -kind service-intentions -name payments-api
consul config delete -kind service-intentions -name database
consul config delete -kind service-defaults -name countdash-api
consul config delete -kind service-defaults -name countdash-web
consul config delete -kind service-defaults -name nginx
consul config delete -kind service-defaults -name frontend
consul config delete -kind service-defaults -name public-api
consul config delete -kind service-defaults -name product-api
consul config delete -kind service-defaults -name payments-api
consul config delete -kind service-defaults -name database

# Remove the Nomad variable
nomad var purge -namespace ingress nomad/jobs/api-gateway/gateway/setup
```

## File index

| File | Kind | Description |
|---|---|---|
| `gateway-listener.hcl` | `api-gateway` | HTTPS listener on port 8447 |
| `inline-certificate.hcl` | instructions only | How to generate and apply the TLS cert |
| `http-route-countdash.hcl` | `http-route` | Routes `api-gateway` → `countdash-web` |
| `http-route-hashicups.hcl` | `http-route` | Routes `api-gateway` → `nginx` |
| `api-gateway.nomad.hcl` | Nomad job | Envoy API Gateway in the `ingress` namespace |
| `service-defaults/` | `service-defaults` | Protocol declarations for all mesh services |
| `intentions/` | `service-intentions` | Allow-list per destination service |
