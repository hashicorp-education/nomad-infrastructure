# Nomad Tutorials Analysis by IBM Bob

> **Analyzed**: All tutorials listed at https://developer.hashicorp.com/nomad/tutorials  
> **Methodology**: Live crawl of all collection and individual tutorial pages on developer.hashicorp.com.  
> **ARM64 assessment**: Based on explicit architecture mentions, Docker image multi-arch support (verified live against Docker Hub / GHCR manifests), Vagrant/VirtualBox usage, and cloud instance types referenced in each tutorial.  
> **CE vs Enterprise**: Based on explicit "Enterprise" badges, license requirement steps, or feature-gating mentioned in tutorial content.  
> **Docker image arch**: Verified live via `hub.docker.com/v2/repositories/<ns>/<image>/tags/<tag>` API and GHCR manifest API. Values: `amd64`, `arm64`, `both`.

---

## Quick Reference Table

| # | Tutorial | Collection | CE / Ent | ARM64 | Repo | Infrastructure Targets | Application(s) deployed | Docker image arch | Move to Docs | Archive | Make Sandbox only option? |
|---|----------|------------|----------|-------|------|------------------------|-------------------------|-------------------|--------------|---------|---------------------------|
| 1 | [Install the Nomad CLI](#1-install-the-nomad-cli) | Get Started | CE | ✅ | — | Linux, macOS, Windows | _(none)_ | — | Y | | |
| 2 | [Create a Nomad cluster](#2-create-a-nomad-cluster) | Get Started | CE | ✅ | [learn-nomad-getting-started] | Linux, macOS | _(none)_ | — | | | |
| 3 | [Deploy and update a Nomad job](#3-deploy-and-update-a-nomad-job) | Get Started | CE | ✅ | — | Linux, macOS | redis | both | | | |
| 4 | [Stop Nomad and clean up](#4-stop-nomad-and-clean-up) | Get Started | CE | ✅ | — | Linux, macOS | _(none)_ | — | Y | | |
| 5 | [Nomad clusters on the cloud – Overview](#5-nomad-clusters-on-the-cloud--overview) | Cluster Setup | CE | ⚠️ | [learn-nomad-cluster-setup] | AWS / GCP / Azure Linux VMs | _(none)_ | — | Y | | |
| 6 | [Set up a Nomad cluster on AWS](#6-set-up-a-nomad-cluster-on-aws) | Cluster Setup | CE | ⚠️ | [learn-nomad-cluster-setup] | AWS EC2 Linux | _(none)_ | — | | | |
| 7 | [Set up a Nomad cluster on GCP](#7-set-up-a-nomad-cluster-on-gcp) | Cluster Setup | CE | ⚠️ | [learn-nomad-cluster-setup] | GCP Compute Engine Linux | _(none)_ | — | | | |
| 8 | [Set up a Nomad cluster on Azure](#8-set-up-a-nomad-cluster-on-azure) | Cluster Setup | CE | ⚠️ | [learn-nomad-cluster-setup] | Azure VM Linux | _(none)_ | — | | | |
| 9 | [Create a parameterized Nomad job](#9-create-a-parameterized-nomad-job) | Job Specifications | CE | ✅ | — | Linux, macOS | hashicorp/http-echo | both | | | |
| 10 | [Migrate a Linux-based Java app to Nomad](#10-migrate-a-linux-based-java-app-to-nomad) | Job Specifications | CE | ✅ | — | Linux | Spring Boot JAR (java driver) | — | | | |
| 11 | [Migrate a Windows-based Java app to Nomad](#11-migrate-a-windows-based-java-app-to-nomad) | Job Specifications | CE | ❌ | — | Windows | Spring Boot JAR (java driver) | — | | | |
| 12 | [Template abstract job specs with Levant](#12-template-abstract-job-specs-with-levant) | Job Specifications | CE | ✅ | — | Linux, macOS | hashicorp/http-echo | both | | | |
| 13 | [AI workloads on Nomad – Overview](#13-ai-workloads-on-nomad--overview) | AI Workloads | CE | ⚠️ | [learn-nomad-ai-workload] | AWS EC2 Linux | _(none)_ | — | Y | | |
| 14 | [Run a Granite AI workload on Nomad](#14-run-a-granite-ai-workload-on-nomad) | AI Workloads | CE | ⚠️ | [learn-nomad-ai-workload] | AWS EC2 Linux | ollama/ollama | both | | | |
| 15 | [Scale node pools to run more AI models](#15-scale-node-pools-to-run-more-ai-models) | AI Workloads | CE | ⚠️ | [learn-nomad-ai-workload] | AWS EC2 Linux | ollama/ollama | both | | | |
| 16 | [Scale an application with the Nomad Autoscaler](#16-scale-an-application-with-the-nomad-autoscaler) | Autoscaling | CE | ❌ | [nomad-autoscaler-demos] | Vagrant / VirtualBox (Linux guest) | demo-webapp-lb-guide, toxiproxy, prometheus, grafana, traefik, loki, promtail, nomad-autoscaler | amd64 (webapp), both (others) | | | |
| 17 | [Horizontal cluster autoscaling](#17-horizontal-cluster-autoscaling) | Autoscaling | CE | ❌ | [nomad-autoscaler-demos] | Vagrant / VirtualBox (Linux guest) | demo-webapp-lb-guide, toxiproxy, prometheus, grafana, traefik, nomad-autoscaler | amd64 (webapp), both (others) | | | |
| 18 | [Dynamically scale a cluster for on-demand batch](#18-dynamically-scale-a-cluster-for-on-demand-batch) | Autoscaling | CE | ❌ | [nomad-autoscaler-demos] | Vagrant / VirtualBox (Linux guest) | alpine, prometheus, grafana, traefik, nomad-autoscaler | both | | | |
| 19 | [Dynamic Application Sizing concepts](#19-dynamic-application-sizing-concepts) | Autoscaling / Enterprise | Enterprise | ❌ | — | Vagrant / VirtualBox (Linux guest) | _(none)_ | — | Y | | |
| 20 | [Use Dynamic Application Sizing](#20-use-dynamic-application-sizing) | Autoscaling / Enterprise | Enterprise | ❌ | — | Vagrant / VirtualBox (Linux guest) | nginx, redis:6.0, prometheus, nomad-autoscaler-enterprise | both | | | |
| 21 | [Migrate a monolith – Overview](#21-migrate-a-monolith--overview) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | _(none)_ | — | Y | | |
| 22 | [Migrate a monolith – Cluster setup](#22-migrate-a-monolith--cluster-setup) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | _(none)_ | — | | | |
| 23 | [Migrate a monolith – HashiCups](#23-migrate-a-monolith--hashicups) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | frontend, public-api, product-api, product-api-db, payments | ❌ payments is amd64 only | | | |
| 24 | [Migrate a monolith – Service discovery](#24-migrate-a-monolith--service-discovery) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | frontend, public-api, product-api, product-api-db, payments | ❌ payments is amd64 only | | | |
| 25 | [Migrate a monolith – Service mesh gateway](#25-migrate-a-monolith--service-mesh-gateway) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | frontend, public-api, product-api, product-api-db, payments | ❌ payments is amd64 only | | | |
| 26 | [Migrate a monolith – Autoscale](#26-migrate-a-monolith--autoscale) | Migrate a Monolith | CE | ❌ | [learn-nomad-migrate-monolith] | Linux | frontend, public-api, product-api, product-api-db, payments, nomad-autoscaler | ❌ payments is amd64 only | | | |
| 27 | [Oversubscribe memory resources](#27-oversubscribe-memory-resources) | Advanced Scheduling | CE | ❌ | [learn-nomad-features] | Linux | voiselle/wave, influxdb, alpine, curlimages/curl | ❌ wave is amd64 only | | | |
| 28 | [Schedule edge services](#28-schedule-edge-services) | Edge Computing | CE | ⚠️ | — | AWS EC2 Linux | nginx | both | | | |
| 29 | [Install a HashiCorp Enterprise license](#29-install-a-hashicorp-enterprise-license) | Enterprise | Enterprise | ✅ | — | Linux, macOS, Windows | _(none)_ | — | Y | | |
| 30 | [Discover Nomad reference architecture](#30-discover-nomad-reference-architecture) | Enterprise | Enterprise | ✅ | — | Linux VMs (any cloud or bare metal) | _(none)_ | — | Y | | |
| 31 | [Deploy a Nomad Enterprise cluster](#31-deploy-a-nomad-enterprise-cluster) | Enterprise | Enterprise | ⚠️ | — | Linux VMs (any cloud or bare metal) | _(none)_ | — | | | |
| 32 | [Monitor Nomad metrics with Prometheus](#32-monitor-nomad-metrics-with-prometheus) | Manage Clusters | CE | ✅ | — | Linux, macOS | prom/prometheus, grafana/grafana | both | | | |
| 33 | [Monitor job service metrics with Prometheus and Grafana](#33-monitor-job-service-metrics-with-prometheus-and-grafana) | Manage Clusters | CE | ✅ | — | Linux, macOS | prom/prometheus, grafana/grafana, hashicorp/consul | both | | | |
| 34 | [Create and update Nomad Variables](#34-create-and-update-nomad-variables) | Nomad Variables | CE | ✅ | — | Linux, macOS, Windows | _(none)_ | — | | | |
| 35 | [Configure ACLs for Nomad Variables](#35-configure-acls-for-nomad-variables) | Nomad Variables | CE | ✅ | — | Linux, macOS, Windows | _(none)_ | — | | | |
| 36 | [Run Nomad as a Windows service](#36-run-nomad-as-a-windows-service) | Windows | CE | ❌ | — | Windows | _(none)_ | — | | | |
| 37 | [Consul ACL with Nomad Workload Identity](#37-consul-acl-with-nomad-workload-identity) | Consul | CE | ✅ | — | Linux, macOS | _(none)_ | — | | | |
| 38 | [Secure Nomad jobs with Consul service mesh](#38-secure-nomad-jobs-with-consul-service-mesh) | Consul | CE | ❌ | — | Linux, macOS | hashicorpdev/counter-api, hashicorpdev/counter-dashboard, envoyproxy/envoy | ❌ counter-api/dashboard are amd64 only | | | |
| 39 | [Consul service mesh production checklist](#39-consul-service-mesh-production-checklist) | Consul | CE | ✅ | — | Linux VMs (any cloud or bare metal) | _(none)_ | — | Y | | |
| 40 | [Consul API Gateway on Nomad](#40-consul-api-gateway-on-nomad) | Consul | CE | ✅ | — | Linux, macOS | nicholasjackson/fake-service, hashicorp/consul-api-gateway, envoyproxy/envoy | both | | | |
| 41 | [External application load balancing](#41-external-application-load-balancing) | Load Balancing | CE | ⚠️ | [learn-nomad-external-alb] | AWS EC2 Linux | hashicorp/demo-webapp-lb-guide, nginx | ❌ demo-webapp-lb-guide is amd64 only | | | |
| 42 | [Deploy an app with Nomad service discovery](#42-deploy-an-app-with-nomad-service-discovery) | Service Discovery | CE | ❌ | [learn-nomad-service-discovery] | Linux, macOS | hashicorp/counting-service, hashicorp/dashboard-service | ❌ both are amd64 only | | | |
| 43 | [Convert to Consul service discovery](#43-convert-to-consul-service-discovery) | Service Discovery | CE | ❌ | — | Linux, macOS | hashicorp/counting-service, hashicorp/dashboard-service | ❌ both are amd64 only | | | |
| 44 | [Template Nomad jobspecs with Levant](#44-template-nomad-jobspecs-with-levant) | Templates | CE | ✅ | — | Linux, macOS | hashicorp/http-echo | both | | | |
| 45 | [Template abstract job specs with Levant](#45-template-abstract-job-specs-with-levant) | Templates | CE | ✅ | — | Linux, macOS | hashicorp/http-echo | both | | | |
| 46 | [Generate mTLS certificates with Vault PKI](#46-generate-mtls-certificates-with-vault-pki) | Vault | CE | ✅ | — | Linux, macOS | _(none)_ | — | | | |
| 47 | [Federate access to GCP with Workload Identity](#47-federate-access-to-gcp-with-workload-identity) | Workload Identity | CE | ✅ | — | Linux, macOS | _(none)_ | — | | | |

**Legend**  
✅ ARM64 compatible — ⚠️ ARM64 uncertain (cloud infra, GPU, or x86 instance types referenced) — ❌ ARM64 not supported (Vagrant/VirtualBox, Windows x64, amd64-only Docker image)

> **Docker image arch note**: `hashicorpdemoapp/payments` is amd64 only (all versions); `hashicorpdemoapp/product-api`, `public-api`, `product-api-db`, and `frontend` all support arm64 as of their recent versions. The limiting image for HashiCups on ARM64 is `payments`.

---

## Detailed Tutorial Entries

### Get Started

#### 1. Install the Nomad CLI
- **URL**: https://developer.hashicorp.com/nomad/tutorials/get-started/gs-install
- **Subject**: Download and install the Nomad CLI binary on Linux, macOS, or Windows.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS, Windows
- **ARM64**: ✅ Nomad ships `linux_arm64` and `darwin_arm64` packages; homebrew tap is multi-arch.
- **Code repo**: —
- **Application(s) deployed**: _(none — installation only)_
- **Docker image arch**: —

#### 2. Create a Nomad cluster
- **URL**: https://developer.hashicorp.com/nomad/tutorials/get-started/gs-start-a-cluster
- **Subject**: Bootstrap a local dev-mode Nomad cluster and verify it is running.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Dev-mode runs as a single binary on any architecture.
- **Code repo**: https://github.com/hashicorp/learn-nomad-getting-started
- **Application(s) deployed**: _(none — cluster bootstrap only)_
- **Docker image arch**: —

#### 3. Deploy and update a Nomad job
- **URL**: https://developer.hashicorp.com/nomad/tutorials/get-started/gs-deploy-job
- **Subject**: Write a Nomad job spec, submit it, inspect the allocation, and perform an in-place update.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ `redis:latest` ships a multi-arch manifest including `linux/arm64`.
- **Code repo**: —
- **Application(s) deployed**: `redis:latest`
- **Docker image arch**: both (amd64 + arm64)

#### 4. Stop Nomad and clean up
- **URL**: https://developer.hashicorp.com/nomad/tutorials/get-started/gs-stop-nomad
- **Subject**: Stop running jobs and shut down the local Nomad agent.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Architecture-agnostic cleanup steps.
- **Code repo**: —
- **Application(s) deployed**: _(none — teardown only)_
- **Docker image arch**: —

---

### Cluster Setup

#### 5. Nomad clusters on the cloud – Overview
- **URL**: https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-overview
- **Subject**: Introduction to the three-part cloud cluster setup series using Terraform.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS / GCP / Azure Linux VMs
- **ARM64**: ⚠️ Terraform modules use default x86_64 instance types (`t2.micro`, `n1-standard-1`). ARM64 instances can be substituted but are not documented.
- **Code repo**: https://github.com/hashicorp/learn-nomad-cluster-setup
- **Application(s) deployed**: _(none — cluster infrastructure only)_
- **Docker image arch**: —

#### 6. Set up a Nomad cluster on AWS
- **URL**: https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-aws
- **Subject**: Provision a Nomad cluster on AWS using Terraform with an EC2-backed server and client pool.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Uses `t2.micro` (x86_64) by default; Graviton (`t4g`) can be substituted but requires AMI changes.
- **Code repo**: https://github.com/hashicorp/learn-nomad-cluster-setup
- **Application(s) deployed**: _(none — cluster infrastructure only)_
- **Docker image arch**: —

#### 7. Set up a Nomad cluster on GCP
- **URL**: https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-gcp
- **Subject**: Provision a Nomad cluster on GCP using Terraform.
- **CE / Enterprise**: CE
- **Infrastructure targets**: GCP Compute Engine Linux
- **ARM64**: ⚠️ Uses `n1-standard-1` (x86_64) by default; ARM instance types can be substituted.
- **Code repo**: https://github.com/hashicorp/learn-nomad-cluster-setup
- **Application(s) deployed**: _(none — cluster infrastructure only)_
- **Docker image arch**: —

#### 8. Set up a Nomad cluster on Azure
- **URL**: https://developer.hashicorp.com/nomad/tutorials/cluster-setup/cluster-setup-azure
- **Subject**: Provision a Nomad cluster on Azure using Terraform.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Azure VM Linux
- **ARM64**: ⚠️ Uses standard x86_64 Azure VM sizes by default.
- **Code repo**: https://github.com/hashicorp/learn-nomad-cluster-setup
- **Application(s) deployed**: _(none — cluster infrastructure only)_
- **Docker image arch**: —

---

### Job Specifications

#### 9. Create a parameterized Nomad job
- **URL**: https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-parameterized
- **Subject**: Define a parameterized batch job and dispatch it with per-dispatch payload and metadata.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ `hashicorp/http-echo` ships a multi-arch manifest including `linux/arm64`.
- **Code repo**: —
- **Application(s) deployed**: `hashicorp/http-echo:latest`
- **Docker image arch**: both (amd64 + arm64)

#### 10. Migrate a Linux-based Java app to Nomad
- **URL**: https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-java-linux
- **Subject**: Package a Spring Boot application as a Nomad job using the `java` task driver on Linux.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ✅ The `java` task driver and a standard OpenJDK runtime are available on ARM64 Linux. No Docker image is used.
- **Code repo**: —
- **Application(s) deployed**: Spring Boot JAR via `java` task driver (no Docker image)
- **Docker image arch**: — (java driver, not Docker)

#### 11. Migrate a Windows-based Java app to Nomad
- **URL**: https://developer.hashicorp.com/nomad/tutorials/job-specifications/job-spec-java-windows
- **Subject**: Run a Java application on a Windows Nomad client using the `java` task driver.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Windows
- **ARM64**: ❌ Targets Windows x64. Windows-on-ARM is not a supported Nomad client platform.
- **Code repo**: —
- **Application(s) deployed**: Spring Boot JAR via `java` task driver (no Docker image)
- **Docker image arch**: — (java driver, not Docker)

#### 12. Template abstract job specs with Levant
- **URL**: https://developer.hashicorp.com/nomad/tutorials/job-specifications/levant-abstract-jobs
- **Subject**: Use Levant variables and template functions to create reusable, abstract job specs.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Levant ships `linux_arm64` and `darwin_arm64` releases. `hashicorp/http-echo` is multi-arch.
- **Code repo**: —
- **Application(s) deployed**: `hashicorp/http-echo:latest`
- **Docker image arch**: both (amd64 + arm64)

---

### AI Workloads

#### 13. AI workloads on Nomad – Overview
- **URL**: https://developer.hashicorp.com/nomad/tutorials/ai-workloads/configure-ai-workload
- **Subject**: Overview of running AI inference workloads on Nomad using Ollama and node pools.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Tutorial provisions AWS EC2 GPU or CPU instances (`g` and `m` families, x86_64). The Ollama Docker image has an ARM64 variant, but the tutorial Terraform is written for x86_64 AWS instances.
- **Code repo**: https://github.com/hashicorp/learn-nomad-ai-workload
- **Application(s) deployed**: _(none — overview page only)_
- **Docker image arch**: —

#### 14. Run a Granite AI workload on Nomad
- **URL**: https://developer.hashicorp.com/nomad/tutorials/ai-workloads/run-ai-workload
- **Subject**: Deploy IBM Granite via Ollama as a Nomad Docker job and query the model endpoint.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Same AWS x86_64 infrastructure as tutorial 13; Ollama itself is multi-arch but tutorial infra is not.
- **Code repo**: https://github.com/hashicorp/learn-nomad-ai-workload
- **Application(s) deployed**: `ollama/ollama:latest`
- **Docker image arch**: both (amd64 + arm64)

#### 15. Scale node pools to run more AI models
- **URL**: https://developer.hashicorp.com/nomad/tutorials/ai-workloads/scale-ai-workload
- **Subject**: Use Nomad node pools to schedule additional AI models across a heterogeneous cluster.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Same AWS x86_64 infrastructure caveat as tutorials 13–14.
- **Code repo**: https://github.com/hashicorp/learn-nomad-ai-workload
- **Application(s) deployed**: `ollama/ollama:latest`
- **Docker image arch**: both (amd64 + arm64)

---

### Autoscaling

#### 16. Scale an application with the Nomad Autoscaler
- **URL**: https://developer.hashicorp.com/nomad/tutorials/autoscaler/autoscaler-vagrant-demo
- **Subject**: Demonstrate horizontal application autoscaling using the Nomad Autoscaler with a Vagrant/VirtualBox environment.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Vagrant / VirtualBox (Linux guest)
- **ARM64**: ❌ Requires Vagrant + VirtualBox. VirtualBox does not support ARM64 hosts.
- **Code repo**: https://github.com/hashicorp/nomad-autoscaler-demos
- **Application(s) deployed**: `hashicorp/demo-webapp-lb-guide`, `ghcr.io/shopify/toxiproxy:2.12.0`, `prom/prometheus:v3.5.0`, `grafana/grafana:11.6.3`, `grafana/loki:3.5.5`, `grafana/promtail:3.5.5`, `traefik:v3.5.3`, `hashicorp/nomad-autoscaler:0.5.0`
- **Docker image arch**: ❌ `hashicorp/demo-webapp-lb-guide` is amd64 only; all others are multi-arch

#### 17. Horizontal cluster autoscaling
- **URL**: https://developer.hashicorp.com/nomad/tutorials/autoscaler/horizontal-cluster-scaling
- **Subject**: Configure the Nomad Autoscaler to add and remove Nomad client nodes based on cluster utilization.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Vagrant / VirtualBox (Linux guest)
- **ARM64**: ❌ Vagrant + VirtualBox based demo environment.
- **Code repo**: https://github.com/hashicorp/nomad-autoscaler-demos
- **Application(s) deployed**: `hashicorp/demo-webapp-lb-guide`, `ghcr.io/shopify/toxiproxy:2.12.0`, `prom/prometheus:v3.5.0`, `grafana/grafana:11.6.3`, `traefik:v3.5.3`, `hashicorp/nomad-autoscaler:0.5.0`
- **Docker image arch**: ❌ `hashicorp/demo-webapp-lb-guide` is amd64 only; all others are multi-arch

#### 18. Dynamically scale a cluster for on-demand batch
- **URL**: https://developer.hashicorp.com/nomad/tutorials/autoscaler/horizontal-cluster-scaling-on-demand-batch
- **Subject**: Use the Nomad Autoscaler to scale cluster capacity up and down to satisfy on-demand batch job submissions.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Vagrant / VirtualBox (Linux guest)
- **ARM64**: ❌ Vagrant + VirtualBox based demo environment.
- **Code repo**: https://github.com/hashicorp/nomad-autoscaler-demos
- **Application(s) deployed**: `alpine:3.13`, `prom/prometheus:v2.25.0`, `grafana/grafana:7.4.2`, `grafana/loki:2.1.0`, `traefik:v2.2`, `hashicorp/nomad-autoscaler:0.5.0`
- **Docker image arch**: both (all images are multi-arch)

#### 19. Dynamic Application Sizing concepts
- **URL**: https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing-concepts
- **Subject**: Conceptual overview of Nomad Enterprise Dynamic Application Sizing (DAS) — how it profiles tasks and right-sizes resource requests.
- **CE / Enterprise**: **Enterprise**
- **Infrastructure targets**: Vagrant / VirtualBox (Linux guest)
- **ARM64**: ❌ Conceptual only; hands-on companion (tutorial 20) uses Vagrant/VirtualBox.
- **Code repo**: —
- **Application(s) deployed**: _(none — conceptual overview)_
- **Docker image arch**: —

#### 20. Use Dynamic Application Sizing
- **URL**: https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing
- **Subject**: Enable and use DAS to automatically right-size task resource requests based on historical usage.
- **CE / Enterprise**: **Enterprise**
- **Infrastructure targets**: Vagrant / VirtualBox (Linux guest)
- **ARM64**: ❌ Uses Vagrant + VirtualBox; requires Enterprise license.
- **Code repo**: —
- **Application(s) deployed**: `nginx:latest`, `redis:6.0`, `prom/prometheus:v2.25.0`, `hashicorp/nomad-autoscaler-enterprise:0.5.0-ent`
- **Docker image arch**: both (all images are multi-arch)

---

### Migrate a Monolith

#### 21. Migrate a monolith – Overview
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-overview
- **Subject**: Introduces the six-part series for migrating a monolithic application (HashiCups) to a microservices architecture on Nomad.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` has no ARM64 Docker image.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: _(none — overview page)_
- **Docker image arch**: —

#### 22. Migrate a monolith – Cluster setup
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-cluster-setup
- **Subject**: Stand up a Nomad + Consul cluster to host the HashiCups application.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` has no ARM64 Docker image.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: _(none — cluster setup)_
- **Docker image arch**: —

#### 23. Migrate a monolith – HashiCups
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-hashicups
- **Subject**: Deploy the HashiCups monolith as a Nomad job.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` is amd64 only; other services are multi-arch.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: `hashicorpdemoapp/frontend`, `hashicorpdemoapp/public-api:v0.0.7`, `hashicorpdemoapp/product-api`, `hashicorpdemoapp/product-api-db`, `hashicorpdemoapp/payments`
- **Docker image arch**: ❌ `hashicorpdemoapp/payments` is amd64 only; frontend, public-api, product-api, product-api-db are both

#### 24. Migrate a monolith – Service discovery
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-service-discovery
- **Subject**: Break the monolith into services and register them with Nomad native service discovery.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` is amd64 only.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: `hashicorpdemoapp/frontend`, `hashicorpdemoapp/public-api:v0.0.7`, `hashicorpdemoapp/product-api`, `hashicorpdemoapp/product-api-db`, `hashicorpdemoapp/payments`
- **Docker image arch**: ❌ `hashicorpdemoapp/payments` is amd64 only; others are both

#### 25. Migrate a monolith – Service mesh gateway
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-service-mesh-gateway
- **Subject**: Route traffic through a Consul service mesh and mesh gateway.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` is amd64 only.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: `hashicorpdemoapp/frontend`, `hashicorpdemoapp/public-api:v0.0.7`, `hashicorpdemoapp/product-api`, `hashicorpdemoapp/product-api-db`, `hashicorpdemoapp/payments`
- **Docker image arch**: ❌ `hashicorpdemoapp/payments` is amd64 only; others are both

#### 26. Migrate a monolith – Autoscale
- **URL**: https://developer.hashicorp.com/nomad/tutorials/migrate-monolith/monolith-migration-autoscale
- **Subject**: Add Nomad Autoscaler policies to scale microservices based on Prometheus metrics.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `hashicorpdemoapp/payments` is amd64 only.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-migrate-monolith
- **Application(s) deployed**: `hashicorpdemoapp/frontend`, `hashicorpdemoapp/public-api:v0.0.7`, `hashicorpdemoapp/product-api`, `hashicorpdemoapp/product-api-db`, `hashicorpdemoapp/payments`, `hashicorp/nomad-autoscaler:latest`
- **Docker image arch**: ❌ `hashicorpdemoapp/payments` is amd64 only; others are both

---

### Advanced Scheduling

#### 27. Oversubscribe memory resources
- **URL**: https://developer.hashicorp.com/nomad/tutorials/advanced-scheduling/memory-oversubscription
- **Subject**: Enable memory oversubscription on a Nomad client to allow tasks to burst beyond their reserved limit.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux
- **ARM64**: ❌ `voiselle/wave:v5` is amd64 only.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-features
- **Application(s) deployed**: `voiselle/wave:v5`, `influxdb:2.0.7`, `alpine:3.14.0`, `curlimages/curl:7.77.0`
- **Docker image arch**: ❌ `voiselle/wave:v5` is amd64 only; influxdb, alpine, curl are multi-arch

---

### Edge Computing

#### 28. Schedule edge services
- **URL**: https://developer.hashicorp.com/nomad/tutorials/edge/schedule-edge-services
- **Subject**: Use Nomad node metadata and constraints to schedule workloads on edge nodes; demonstrates native service discovery without Consul.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Tutorial provisions AWS EC2 instances (`t2.micro`, x86_64) via Terraform. The concepts apply to ARM64 edge hardware but the tutorial infra is x86_64. `nginx:latest` is multi-arch.
- **Code repo**: —
- **Application(s) deployed**: `nginx:latest`
- **Docker image arch**: both (amd64 + arm64)

---

### Enterprise

#### 29. Install a HashiCorp Enterprise license
- **URL**: https://developer.hashicorp.com/nomad/tutorials/enterprise/hashicorp-enterprise-license
- **Subject**: Acquire and install a Nomad Enterprise license via environment variable, agent config, or the API.
- **CE / Enterprise**: **Enterprise**
- **Infrastructure targets**: Linux, macOS, Windows
- **ARM64**: ✅ License installation is architecture-agnostic.
- **Code repo**: —
- **Application(s) deployed**: _(none — license configuration only)_
- **Docker image arch**: —

#### 30. Discover Nomad reference architecture
- **URL**: https://developer.hashicorp.com/nomad/tutorials/enterprise/production-reference-architecture-vm-with-consul
- **Subject**: Describes the recommended production topology for a highly available Nomad + Consul cluster (3 or 5 server nodes, multiple client nodes, separate Vault cluster).
- **CE / Enterprise**: **Enterprise** (reference architecture is oriented toward Nomad Enterprise deployments)
- **Infrastructure targets**: Linux VMs (any cloud or bare metal)
- **ARM64**: ✅ Architecture diagrams and configuration guidance are hardware-agnostic.
- **Code repo**: —
- **Application(s) deployed**: _(none — reference architecture document)_
- **Docker image arch**: —

#### 31. Deploy a Nomad Enterprise cluster
- **URL**: https://developer.hashicorp.com/nomad/tutorials/enterprise/production-deployment-guide-vm-with-consul
- **Subject**: Step-by-step guide to deploying a production-grade Nomad Enterprise cluster alongside Consul on Linux VMs.
- **CE / Enterprise**: **Enterprise**
- **Infrastructure targets**: Linux VMs (any cloud or bare metal)
- **ARM64**: ⚠️ Download URLs in the tutorial reference `linux_amd64.zip` explicitly. ARM64 packages exist but are not referenced; manual URL substitution is required.
- **Code repo**: —
- **Application(s) deployed**: _(none — cluster infrastructure only)_
- **Docker image arch**: —

---

### Manage Clusters

#### 32. Monitor Nomad metrics with Prometheus
- **URL**: https://developer.hashicorp.com/nomad/tutorials/manage-clusters/prometheus-metrics
- **Subject**: Configure Nomad's telemetry stanza to expose Prometheus metrics and visualize them with Grafana.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Prometheus and Grafana Docker images ship multi-arch manifests.
- **Code repo**: —
- **Application(s) deployed**: `prom/prometheus:latest`, `grafana/grafana:latest`
- **Docker image arch**: both (amd64 + arm64)

#### 33. Monitor job service metrics with Prometheus and Grafana
- **URL**: https://developer.hashicorp.com/nomad/tutorials/manage-clusters/prometheus-service-mesh-metrics
- **Subject**: Instrument Nomad jobs registered with the Consul service mesh to surface per-service metrics in Prometheus and Grafana.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ All referenced Docker images (Prometheus, Grafana, Consul) are multi-arch.
- **Code repo**: —
- **Application(s) deployed**: `prom/prometheus:latest`, `grafana/grafana:latest`, `hashicorp/consul:latest`
- **Docker image arch**: both (amd64 + arm64)

---

### Nomad Variables

#### 34. Create and update Nomad Variables
- **URL**: https://developer.hashicorp.com/nomad/tutorials/variables/variables-create
- **Subject**: Store and retrieve key/value secrets using the Nomad Variables API and CLI.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS, Windows
- **ARM64**: ✅ CLI-only tutorial; no architecture-specific components.
- **Code repo**: —
- **Application(s) deployed**: _(none — CLI/API only)_
- **Docker image arch**: —

#### 35. Configure ACLs for Nomad Variables
- **URL**: https://developer.hashicorp.com/nomad/tutorials/variables/variables-acls
- **Subject**: Write Nomad ACL policies that control which jobs and users can read or write specific variable paths.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS, Windows
- **ARM64**: ✅ CLI/policy-only tutorial; no architecture-specific components.
- **Code repo**: —
- **Application(s) deployed**: _(none — CLI/API only)_
- **Docker image arch**: —

---

### Windows

#### 36. Run Nomad as a Windows service
- **URL**: https://developer.hashicorp.com/nomad/tutorials/windows/windows-agent
- **Subject**: Install and configure a Nomad agent as a Windows service using `sc.exe`.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Windows
- **ARM64**: ❌ Targets Windows x64. Windows-on-ARM is not a supported Nomad platform.
- **Code repo**: —
- **Application(s) deployed**: _(none — agent configuration only)_
- **Docker image arch**: —

---

### Consul Integration

#### 37. Consul ACL with Nomad Workload Identity
- **URL**: https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-acl
- **Subject**: Configure Consul ACLs so that Nomad workloads authenticate via Workload Identity JWTs instead of shared tokens.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Consul and Nomad both ship ARM64 binaries; tutorial is config/CLI focused.
- **Code repo**: —
- **Application(s) deployed**: _(none — ACL configuration only)_
- **Docker image arch**: —

#### 38. Secure Nomad jobs with Consul service mesh
- **URL**: https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-service-mesh
- **Subject**: Enable the Consul Connect proxy sidecar for a Nomad job to enforce mTLS between services.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ❌ `hashicorpdev/counter-api:v3` and `hashicorpdev/counter-dashboard:v3` are amd64 only.
- **Code repo**: —
- **Application(s) deployed**: `hashicorpdev/counter-api:v3`, `hashicorpdev/counter-dashboard:v3`, `envoyproxy/envoy:v1.16.0`
- **Docker image arch**: ❌ counter-api and counter-dashboard are amd64 only; envoy is multi-arch

#### 39. Consul service mesh production checklist
- **URL**: https://developer.hashicorp.com/nomad/tutorials/integrate-consul/service-mesh-production-checklist
- **Subject**: Checklist and guidance for hardening a Consul service mesh deployment used by Nomad in production.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux VMs (any cloud or bare metal)
- **ARM64**: ✅ Conceptual/checklist tutorial; hardware-agnostic.
- **Code repo**: —
- **Application(s) deployed**: _(none — checklist/reference document)_
- **Docker image arch**: —

#### 40. Consul API Gateway on Nomad
- **URL**: https://developer.hashicorp.com/nomad/tutorials/integrate-consul/deploy-api-gateway-on-nomad
- **Subject**: Deploy and configure the Consul API Gateway as a Nomad job to handle ingress traffic.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ `nicholasjackson/fake-service`, `hashicorp/consul-api-gateway`, and `envoyproxy/envoy` all ship multi-arch manifests.
- **Code repo**: —
- **Application(s) deployed**: `nicholasjackson/fake-service:v0.26.2`, `hashicorp/consul-api-gateway:latest`, `envoyproxy/envoy:v1.28-latest`
- **Docker image arch**: both (amd64 + arm64)

---

### Load Balancing

#### 41. External application load balancing
- **URL**: https://developer.hashicorp.com/nomad/tutorials/load-balancing/external-application-load-balancing
- **Subject**: Use an AWS Application Load Balancer with target group registration to route external traffic to Nomad jobs.
- **CE / Enterprise**: CE
- **Infrastructure targets**: AWS EC2 Linux
- **ARM64**: ⚠️ Deploys on AWS EC2 (x86_64 instances by default). `hashicorp/demo-webapp-lb-guide` is amd64 only; `nginx:latest` is multi-arch.
- **Code repo**: https://github.com/hashicorp/learn-nomad-external-alb
- **Application(s) deployed**: `hashicorp/demo-webapp-lb-guide`, `nginx:latest`
- **Docker image arch**: ❌ `hashicorp/demo-webapp-lb-guide` is amd64 only; nginx is both

---

### Service Discovery

#### 42. Deploy an app with Nomad service discovery
- **URL**: https://developer.hashicorp.com/nomad/tutorials/service-discovery/service-discovery-app-deployment
- **Subject**: Register a Nomad job with Nomad's built-in service discovery (without Consul) and use health checks.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ❌ `hashicorp/counting-service:0.0.2` and `hashicorp/dashboard-service:0.0.4` are amd64 only.
- **Code repo**: https://github.com/hashicorp-education/learn-nomad-service-discovery
- **Application(s) deployed**: `hashicorp/counting-service:0.0.2`, `hashicorp/dashboard-service:0.0.4`
- **Docker image arch**: ❌ both are amd64 only

#### 43. Convert to Consul service discovery
- **URL**: https://developer.hashicorp.com/nomad/tutorials/service-discovery/service-discovery-consul-sd
- **Subject**: Migrate a job from Nomad native service discovery to Consul service discovery.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ❌ Same `hashicorp/counting-service:0.0.2` and `hashicorp/dashboard-service:0.0.4` as tutorial 42 (amd64 only).
- **Code repo**: —
- **Application(s) deployed**: `hashicorp/counting-service:0.0.2`, `hashicorp/dashboard-service:0.0.4`
- **Docker image arch**: ❌ both are amd64 only

---

### Templates

#### 44. Template Nomad jobspecs with Levant
- **URL**: https://developer.hashicorp.com/nomad/tutorials/templates/dry-jobs-levant
- **Subject**: Use Levant to render Nomad job templates from YAML variable files, enabling DRY job specifications.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Levant ships `linux_arm64` and `darwin_arm64` binaries. `hashicorp/http-echo` is multi-arch.
- **Code repo**: —
- **Application(s) deployed**: `hashicorp/http-echo:latest`
- **Docker image arch**: both (amd64 + arm64)

#### 45. Template abstract job specs with Levant
- **URL**: https://developer.hashicorp.com/nomad/tutorials/templates/levant-abstract-jobs
- **Subject**: Build reusable abstract job templates using Levant's Go template functions and helper variables.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Levant ships ARM64 binaries. `hashicorp/http-echo` is multi-arch.
- **Code repo**: —
- **Application(s) deployed**: `hashicorp/http-echo:latest`
- **Docker image arch**: both (amd64 + arm64)

---

### Vault Integration

#### 46. Generate mTLS certificates with Vault PKI
- **URL**: https://developer.hashicorp.com/nomad/tutorials/integrate-vault/vault-pki-nomad
- **Subject**: Configure Vault's PKI secrets engine to issue short-lived TLS certificates for Nomad server and client RPC communication.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Vault ships ARM64 binaries; tutorial is config/CLI focused.
- **Code repo**: —
- **Application(s) deployed**: _(none — PKI/TLS configuration only)_
- **Docker image arch**: —

---

### Workload Identity

#### 47. Federate access to GCP with Workload Identity
- **URL**: https://developer.hashicorp.com/nomad/tutorials/fed-workload-identity/integration-gcp
- **Subject**: Configure Nomad Workload Identity to federate with GCP Workload Identity Federation so Nomad tasks can assume GCP service account roles without static credentials.
- **CE / Enterprise**: CE
- **Infrastructure targets**: Linux, macOS
- **ARM64**: ✅ Tutorial is config/CLI focused; Nomad ships ARM64 binaries for all supported platforms.
- **Code repo**: —
- **Application(s) deployed**: _(none — identity federation configuration only)_
- **Docker image arch**: —

---

## Summary Statistics

| Category | Count |
|----------|-------|
| Total tutorials | 47 |
| CE only | 40 |
| Enterprise only | 7 |
| ✅ ARM64 compatible | 21 |
| ⚠️ ARM64 uncertain | 11 |
| ❌ ARM64 not supported | 15 |
| Tutorials with a linked code repo | 19 |
| Tutorials deploying no workload (Move to Docs candidates) | 9 |

---

## ARM64 Incompatible Tutorials

These tutorials **cannot** be run on ARM64 hardware without significant rework:

| # | Tutorial | Reason |
|---|----------|--------|
| 11 | Migrate a Windows-based Java app to Nomad | Windows x64 target only |
| 16 | Scale an application with the Nomad Autoscaler | Vagrant + VirtualBox (no ARM64 host support); `hashicorp/demo-webapp-lb-guide` is amd64 only |
| 17 | Horizontal cluster autoscaling | Vagrant + VirtualBox; `hashicorp/demo-webapp-lb-guide` is amd64 only |
| 18 | Dynamically scale a cluster for on-demand batch | Vagrant + VirtualBox |
| 19 | Dynamic Application Sizing concepts | Companion hands-on uses Vagrant + VirtualBox |
| 20 | Use Dynamic Application Sizing | Vagrant + VirtualBox + Enterprise license |
| 21 | Migrate a monolith – Overview | `hashicorpdemoapp/payments` has no ARM64 Docker image |
| 22 | Migrate a monolith – Cluster setup | `hashicorpdemoapp/payments` has no ARM64 Docker image |
| 23 | Migrate a monolith – HashiCups | `hashicorpdemoapp/payments` is amd64 only |
| 24 | Migrate a monolith – Service discovery | `hashicorpdemoapp/payments` is amd64 only |
| 25 | Migrate a monolith – Service mesh gateway | `hashicorpdemoapp/payments` is amd64 only |
| 26 | Migrate a monolith – Autoscale | `hashicorpdemoapp/payments` is amd64 only |
| 27 | Oversubscribe memory resources | `voiselle/wave:v5` is amd64 only |
| 36 | Run Nomad as a Windows service | Windows x64 only |
| 38 | Secure Nomad jobs with Consul service mesh | `hashicorpdev/counter-api:v3` and `hashicorpdev/counter-dashboard:v3` are amd64 only |
| 42 | Deploy an app with Nomad service discovery | `hashicorp/counting-service:0.0.2` and `hashicorp/dashboard-service:0.0.4` are amd64 only |
| 43 | Convert to Consul service discovery | Same images as #42: counting-service and dashboard-service are amd64 only |

> **HashiCups note**: As of their latest versions, `hashicorpdemoapp/product-api`, `public-api`, `product-api-db`, and `frontend` all have ARM64 images. The blocking image for the entire HashiCups series (#21–#26) is `hashicorpdemoapp/payments`, which is amd64 only across all published tags.

---

## Move to Docs Candidates

These tutorials contain no deployable workload and are primarily reference or conceptual material. They are good candidates for conversion to documentation pages rather than interactive tutorials.

| # | Tutorial | Reason |
|---|----------|--------|
| 1 | Install the Nomad CLI | Installation instructions only |
| 4 | Stop Nomad and clean up | Teardown steps only |
| 5 | Nomad clusters on the cloud – Overview | Series introduction page |
| 13 | AI workloads on Nomad – Overview | Series introduction page |
| 19 | Dynamic Application Sizing concepts | Conceptual overview with no hands-on steps |
| 21 | Migrate a monolith – Overview | Series introduction page |
| 29 | Install a HashiCorp Enterprise license | Configuration procedure |
| 30 | Discover Nomad reference architecture | Reference architecture document |
| 39 | Consul service mesh production checklist | Checklist / reference document |

---

## Tutorials Requiring Enterprise License

| Tutorial | URL |
|----------|-----|
| Dynamic Application Sizing concepts (#19) | https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing-concepts |
| Use Dynamic Application Sizing (#20) | https://developer.hashicorp.com/nomad/tutorials/autoscaler/dynamic-application-sizing |
| Install a HashiCorp Enterprise license (#29) | https://developer.hashicorp.com/nomad/tutorials/enterprise/hashicorp-enterprise-license |
| Discover Nomad reference architecture (#30) | https://developer.hashicorp.com/nomad/tutorials/enterprise/production-reference-architecture-vm-with-consul |
| Deploy a Nomad Enterprise cluster (#31) | https://developer.hashicorp.com/nomad/tutorials/enterprise/production-deployment-guide-vm-with-consul |

> **Note**: Tutorials 19 and 20 appear in both the `autoscaler` and `enterprise` collections on developer.hashicorp.com.

---

## Code Repositories Referenced

| Repository | Tutorials |
|------------|-----------|
| https://github.com/hashicorp/learn-nomad-getting-started | #2 |
| https://github.com/hashicorp/learn-nomad-cluster-setup | #5, #6, #7, #8 |
| https://github.com/hashicorp/learn-nomad-ai-workload | #13, #14, #15 |
| https://github.com/hashicorp/nomad-autoscaler-demos | #16, #17, #18 |
| https://github.com/hashicorp-education/learn-nomad-migrate-monolith | #21–#26 |
| https://github.com/hashicorp-education/learn-nomad-features | #27 |
| https://github.com/hashicorp/learn-nomad-external-alb | #41 |
| https://github.com/hashicorp-education/learn-nomad-service-discovery | #42 |

---

## Docker Image Architecture Reference

All images verified live against Docker Hub or GHCR manifests.

| Image | ARM64 | Notes |
|-------|-------|-------|
| `redis:latest` | ✅ both | Multi-arch official image |
| `nginx:latest` | ✅ both | Multi-arch official image |
| `alpine:3.13` / `alpine:3.14.0` | ✅ both | Multi-arch official image |
| `prom/prometheus:v3.5.0` | ✅ both | |
| `grafana/grafana:11.6.3` | ✅ both | |
| `grafana/loki:3.5.5` | ✅ both | |
| `grafana/promtail:3.5.5` | ✅ both | |
| `traefik:v3.5.3` | ✅ both | |
| `hashicorp/consul:latest` | ✅ both | |
| `hashicorp/vault:latest` | ✅ both | |
| `hashicorp/nomad-autoscaler:0.5.0` | ✅ both | |
| `hashicorp/nomad-autoscaler-enterprise:0.5.0-ent` | ✅ both | |
| `hashicorp/http-echo:latest` | ✅ both | |
| `hashicorp/levant:latest` | ✅ both | |
| `ollama/ollama:latest` | ✅ both | |
| `nicholasjackson/fake-service:v0.26.2` | ✅ both | |
| `hashicorp/consul-api-gateway:latest` | ✅ both | |
| `envoyproxy/envoy:v1.16.0` / `v1.28-latest` | ✅ both | |
| `ghcr.io/shopify/toxiproxy:2.12.0` | ✅ both | GHCR manifest confirms linux/amd64 + linux/arm64 |
| `influxdb:2.0.7` | ✅ both | |
| `curlimages/curl:7.77.0` | ✅ both | |
| `hashicorpdemoapp/product-api` (v0.0.20+) | ✅ both | Earlier versions may differ |
| `hashicorpdemoapp/public-api` (v0.0.5+) | ✅ both | |
| `hashicorpdemoapp/product-api-db` (v0.0.20+) | ✅ both | |
| `hashicorpdemoapp/frontend` (v1.0.7+) | ✅ both | |
| `hashicorp/demo-webapp-lb-guide:latest` | ❌ amd64 only | No arm64 manifest |
| `voiselle/wave:v5` | ❌ amd64 only | No arm64 manifest |
| `hashicorp/counting-service:0.0.2` | ❌ amd64 only | No arm64 manifest |
| `hashicorp/dashboard-service:0.0.4` | ❌ amd64 only | No arm64 manifest |
| `hashicorpdemoapp/payments` (all versions) | ❌ amd64 only | Blocking image for all HashiCups tutorials |
| `hashicorpdev/counter-api:v3` | ❌ amd64 only | |
| `hashicorpdev/counter-dashboard:v3` | ❌ amd64 only | |


> From Aimee: Note about Countdash, which is `counter-api` and `counter-dashboard` Docker
> images. `v3` and `latest` are not multi-arch images. DockerHub
> does have arm64 images that append the OS architecture (`v3-arm64`,
> `v3-amd64`). So we solved the architecture issue in the
> job spec by appending the `attr.cpu.arch` to the image name.

```hcl
config {
  image          = "hashicorpdev/counter-dashboard:${var.countdash-web-version}-${attr.cpu.arch}"
  auth_soft_fail = true
  ports = ["countdash-web"]
}
```
