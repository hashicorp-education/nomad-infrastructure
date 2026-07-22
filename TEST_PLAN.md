# Test Plan: PR #1 — Initial code commit (`aimeeu-initial` → `main`)

Reviewer checklist for testing every deployment scenario this repo supports,
on both AWS and Multipass. Each scenario links to its full step-by-step
instructions in [DEPLOY_CLUSTER_GUIDE.md](DEPLOY_CLUSTER_GUIDE.md) — this
document is the condensed, pass/fail-oriented companion for PR review, not a
replacement for that guide.

## Platform support matrix

| Scenario | AWS | Multipass | Notes |
|---|:---:|:---:|---|
| Get Started (single-node) | ✅ | ✅ | No cloud dependency either way |
| A — Consul only | ✅ | ✅ | |
| B — Nomad only | ✅ | ✅ | Nomad's `retry_join` never uses cloud auto-join, on either platform |
| C — Consul + Nomad + service discovery | ✅ | ✅ **verified** | Confirmed clean end-to-end run per [`_context/wiki/multipass-local-testing-plan.md`](_context/wiki/multipass-local-testing-plan.md) |
| D — + workload identity | ✅ | ⚠️ expected to work, **not yet explicitly verified live** | No AWS-only code path added on top of C; worth a live pass as part of this review |
| E — + service mesh + API Gateway | ✅ | ❌ **not supported** | See "Known gap" below |
| F — Nomad + Vault | ✅ | ⚠️ expected to work, **not yet explicitly verified live** | No AWS-only code path; worth a live pass as part of this review |

### Known gap: Option E does not run on Multipass

`ansible/playbooks/consul_nomad_service_mesh.yaml` hardcodes
`consul_cloud_auto_join_enabled: true` on both the server and client plays
(unlike every other Consul-touching playbook in this repo, which reads
`consul_use_aws_cloud_join` from the inventory and defaults to `false` on
Multipass). That renders a Consul `retry_join` against the AWS EC2 API, which
doesn't exist on Multipass VMs. Separately, `terraform/multipass/variables.tf`
has no `ingress_client_count` equivalent, so the dedicated public ingress
client Option E depends on can't even be provisioned there. **Test Option E
on AWS only** — do not spend review time trying it on Multipass; this is a
pre-existing gap, not something to file as a new bug during this review
(though a follow-up issue to fix it would be welcome).

## Prerequisites (both platforms)

```bash
git clone <this-repo> && cd nomad-infrastructure
git checkout aimeeu-initial   # or check out this PR's branch directly
cd ansible
ansible-galaxy install -r requirements.yaml
```

## Platform setup

### AWS

```bash
cd terraform/aws
cp terraform.tfvars.example terraform.tfvars   # edit as needed per scenario below
terraform init
terraform apply
```

Requires AWS credentials configured — see
[AWS credentials](DEPLOY_CLUSTER_GUIDE.md#aws-credentials) in the guide.

### Multipass

```bash
brew install --cask multipass   # if not already installed
cd terraform/multipass
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply
multipass list   # confirm VMs are running
```

See [`terraform/multipass/README.md`](terraform/multipass/README.md) for
full detail. **Run AWS or Multipass, never both at once** — both workspaces
write to the same `ansible/inventory.ini`.

Both workspaces write `ansible/inventory.ini` directly, so every command
below is identical on both platforms — only the Terraform apply step and the
IP you browse to differ (public EC2 IP vs. `multipass list` IP).

---

## Per-scenario checklists

For each scenario: set the `terraform.tfvars` noted, apply, run the deploy
command, then run through the verification checklist. Tear down
(`ansible-playbook -i inventory.ini teardown.yaml` + `terraform destroy`)
before moving to the next scenario, since scenarios reconfigure the same
nodes.

### Scenario Get Started — single-node agent

Full detail: [Option Get Started](DEPLOY_CLUSTER_GUIDE.md#option-get-started-single-node-nomad-agent----deploy_get_startedyaml)

- [ ] `terraform.tfvars`: `server_count = 1`, `client_count = 0`
- [ ] `ansible-playbook -i inventory.ini deploy_get_started.yaml` completes with `failed=0`
- [ ] `export NOMAD_ADDR=http://<server-ip>:4646` (printed by the completion banner)
- [ ] `nomad node status` shows one combined server+client node, `ready`
- [ ] Nomad UI reachable at `http://<server-ip>:4646` with no TLS/login prompt

### Scenario A — Consul only

Full detail: [Option A](DEPLOY_CLUSTER_GUIDE.md#option-a-consul-cluster-only----deploy_consulyaml)

- [ ] Default `terraform.tfvars` (`server_count = 3`, `client_count = 2`)
- [ ] `ansible-playbook -i inventory.ini deploy_consul.yaml` completes with `failed=0`
- [ ] `source ./set-cluster-env.sh`
- [ ] `consul members` shows 3 servers + 2 clients, all `alive`
- [ ] Consul UI reachable at `https://<server-ip>:8443/ui`, logs in with `CONSUL_HTTP_TOKEN`

### Scenario B — Nomad only

Full detail: [Option B](DEPLOY_CLUSTER_GUIDE.md#option-b-nomad-cluster-only----deploy_nomadyaml)

- [ ] Default `terraform.tfvars`
- [ ] `ansible-playbook -i inventory.ini deploy_nomad.yaml` completes with `failed=0`
- [ ] `source ./set-cluster-env.sh`
- [ ] `nomad server members` shows 3 servers, one `Leader`
- [ ] `nomad node status` shows 2 clients, `ready`
- [ ] Deploy `nomad-jobs/nomad-sd/countdash-nomad-service-discovery.nomad.hcl`, confirm `nomad job status countdash-nomad-sd` shows `running`, then `nomad job stop -purge countdash-nomad-sd`

### Scenario C — Consul + Nomad with service discovery

Full detail: [Option C](DEPLOY_CLUSTER_GUIDE.md#option-c-consul--nomad-with-service-discovery----deploy_consul_nomad_sdyaml)

- [ ] Default `terraform.tfvars`
- [ ] `ansible-playbook -i inventory.ini deploy_consul_nomad_sd.yaml` completes with `failed=0`
- [ ] `source ./set-cluster-env.sh`
- [ ] `consul catalog services` includes `nomad`, `nomad-client`
- [ ] Deploy `nomad-jobs/consul-sd/countdash-consul-service-discovery.nomad.hcl`, confirm the web UI loads and the counting service is reachable (not "unreachable"), then `nomad job stop -purge countdash-consul-sd`

### Scenario D — + workload identity

Full detail: [Option D](DEPLOY_CLUSTER_GUIDE.md#option-d-consul--nomad-with-service-discovery-and-workload-identity----deploy_consul_nomad_wiyaml)

- [ ] Default `terraform.tfvars`
- [ ] `ansible-playbook -i inventory.ini deploy_consul_nomad_wi.yaml` completes with `failed=0`
- [ ] `consul acl auth-method list` includes `nomad-workloads`
- [ ] `consul acl auth-method read nomad-workloads` — `Config.JWKSUrl` points at the correct first server's private IP
- [ ] `consul acl binding-rule list` shows rules for the `nomad_service` and task workload selectors
- [ ] Redeploy the Consul-SD Countdash job from Scenario C and confirm it still works (now via workload identity, no static token)
- [ ] **Multipass only**: this is the "not yet explicitly verified" combination flagged in the platform matrix above — please note pass/fail explicitly in review feedback

### Scenario E — + service mesh + API Gateway (AWS only)

Full detail: [Option E](DEPLOY_CLUSTER_GUIDE.md#option-e-consul--nomad-with-service-discovery-workload-identity-and-service-mesh----deploy_consul_nomad_meshyaml)
and [`nomad-jobs/consul-mesh/README.md`](nomad-jobs/consul-mesh/README.md)
for the application-level deploy steps (service-defaults → intentions → TLS
cert → gateway listener → http-route → mesh app job → API Gateway job).

- [ ] `terraform.tfvars`: `ingress_client_count = 1` **set before** `terraform apply` (adds the dedicated public ingress client + security group)
- [ ] `ansible-playbook -i inventory.ini deploy_consul_nomad_mesh.yaml` completes with `failed=0`
- [ ] `nomad node status -verbose <node-id> | grep consul.connect` → `true` on every client
- [ ] `nomad node status -verbose <node-id> | grep nodeRole` → `meta.nodeRole = ingress` on exactly one client
- [ ] Deploy Countdash (`countdash-transparent-proxy.nomad.hcl`) and HashiCups (`hashicups-consul-service-mesh.nomad.hcl`) mesh jobs plus the API Gateway per the mesh README
- [ ] `https://<ingress-client-ip>:8447/` — Countdash loads, backend counting service reachable
- [ ] `https://<ingress-client-ip>:8448/` — HashiCups loads, all services reachable
- [ ] Both URLs work **simultaneously** in separate browser tabs (this is the dual-listener change this PR adds — confirm it's not still exclusive/path-based)
- [ ] `curl -k https://<internal-client-ip>:8447/` from outside the VPC times out or refuses (confirms the ingress-only security-group split — app ports must not be reachable on the non-ingress clients)

### Scenario F — Nomad + Vault (workload identity)

Full detail: [Option F](DEPLOY_CLUSTER_GUIDE.md#option-f-nomad--vault-with-workload-identity----deploy_nomad_vaultyaml)

- [ ] Default `terraform.tfvars` (no Consul needed for this scenario)
- [ ] `ansible-playbook -i inventory.ini deploy_nomad_vault.yaml` completes with `failed=0`
- [ ] `vault status` — `Initialized = true`, `Sealed = false`
- [ ] `vault auth list` includes `jwt-nomad/`
- [ ] `vault secrets list` includes `secret/`
- [ ] Run a job with a `vault {}` block, confirm it fetches a secret with no static Vault token in the job spec
- [ ] **Multipass only**: not yet explicitly verified — please note pass/fail explicitly in review feedback

---

## Cross-cutting checks (either platform, any scenario)

- [ ] `ansible-playbook -i inventory.ini teardown.yaml` completes with `failed=0` on **all** hosts, including any host that ran a mesh/Docker workload during this review (this PR fixes two "Device or resource busy" teardown failures — leftover Nomad alloc `secrets/` tmpfs mounts and leftover Docker overlay2/shm mounts — worth deliberately testing teardown right after a scenario that ran containers, e.g. C, E, or F, to exercise the fix)
- [ ] `source ./set-cluster-env.sh` / `source ./unset-cluster-env.sh` — exports/unsets only the variables whose token files exist for the scenario just run
- [ ] Self-signed CA warning appears in-browser for both UIs as described in [Access the UIs](DEPLOY_CLUSTER_GUIDE.md#access-the-uis); Firefox's click-through works without importing the CA

## Reporting results

Note pass/fail per scenario/platform combination as a PR review comment,
especially for the three ⚠️/❌ rows in the platform matrix (D and F on
Multipass, E anywhere but AWS) — those are the combinations this PR hasn't
had an explicit live pass on yet.
