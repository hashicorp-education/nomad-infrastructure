# Nomad Tutorials - Container Registry Analysis

This document catalogs container images used in HashiCorp Nomad tutorials and identifies their source container registries.

## Summary

Based on analysis of Nomad tutorial repositories, the following container registries are used:

- **Docker Hub**: Official Docker images (redis)
- **GitHub Container Registry (ghcr.io)**: HashiCorp Education custom application images

## Detailed Findings

| Tutorial Name | Tutorial URL | GitHub Repository | Job Spec File | Application Image | Container Registry |
|---------------|--------------|-------------------|---------------|-------------------|-------------------|
| Get Started with Nomad | https://developer.hashicorp.com/nomad/tutorials/get-started | https://github.com/hashicorp-education/learn-nomad-getting-started | pytechco-redis.nomad.hcl | redis:7.0.7-alpine | Docker Hub |
| Get Started with Nomad | https://developer.hashicorp.com/nomad/tutorials/get-started | https://github.com/hashicorp-education/learn-nomad-getting-started | pytechco-setup.nomad.hcl | ghcr.io/hashicorp-education/learn-nomad-getting-started/ptc-setup:1.0 | GitHub Container Registry |
| Get Started with Nomad | https://developer.hashicorp.com/nomad/tutorials/get-started | https://github.com/hashicorp-education/learn-nomad-getting-started | pytechco-web.nomad.hcl | ghcr.io/hashicorp-education/learn-nomad-getting-started/ptc-web:1.0 | GitHub Container Registry |
| Get Started with Nomad | https://developer.hashicorp.com/nomad/tutorials/get-started | https://github.com/hashicorp-education/learn-nomad-getting-started | pytechco-employee.nomad.hcl | ghcr.io/hashicorp-education/learn-nomad-getting-started/ptc-employee:1.0 | GitHub Container Registry |

## Additional Tutorial Repositories Analyzed

### Consul + Nomad VM Tutorial

**Repository**: https://github.com/hashicorp-education/learn-consul-nomad-vm  
**Tutorial**: Cracking the monolith with Consul and Nomad

| Job Spec File | Application Image | Container Registry |
|---------------|-------------------|-------------------|
| 01.hashicups.nomad.hcl | hashicorpdemoapp/product-api-db:v0.0.22 | Docker Hub |
| 01.hashicups.nomad.hcl | hashicorpdemoapp/product-api:v0.0.22 | Docker Hub |
| 01.hashicups.nomad.hcl | hashicorpdemoapp/payments:v0.0.16 | Docker Hub |
| 01.hashicups.nomad.hcl | hashicorpdemoapp/public-api:v0.0.7 | Docker Hub |
| 01.hashicups.nomad.hcl | hashicorpdemoapp/frontend:v1.0.9 | Docker Hub |
| 01.hashicups.nomad.hcl | nginx:alpine | Docker Hub |
| 02.hashicups.nomad.hcl | hashicorpdemoapp/* (multiple services) | Docker Hub |
| 03.hashicups.nomad.hcl | hashicorpdemoapp/* (multiple services) | Docker Hub |
| 04.api-gateway.nomad.hcl | hashicorpdemoapp/* (multiple services) | Docker Hub |
| 04.hashicups.nomad.hcl | hashicorpdemoapp/* (multiple services) | Docker Hub |
| 05.autoscaler.nomad.hcl | hashicorp/nomad-autoscaler:0.4.5 | Docker Hub |
| 05.hashicups.nomad.hcl | hashicorpdemoapp/* (multiple services) | Docker Hub |

### Workload Identity Federation Tutorial

**Repository**: https://github.com/hashicorp-education/learn-nomad-workload-identity-federation  
**Tutorial**: Workload Identity Federation

| Job Spec File | Application Image | Container Registry |
|---------------|-------------------|-------------------|
| proxy.nomad.hcl | nginx:mainline | Docker Hub |

### Nomad Edge Deployment Tutorial

**Repository**: https://github.com/hashicorp-education/learn-nomad-edge  
**Tutorial**: Edge deployment tutorials

| Job Spec File | Application Image | Container Registry |
|---------------|-------------------|-------------------|
| hashicups-edge.nomad.hcl | hashicorpdemoapp/payments:v0.0.12 | Docker Hub |
| hashicups-edge.nomad.hcl | hashicorpdemoapp/public-api:v0.0.6 | Docker Hub |
| hashicups-edge.nomad.hcl | hashicorpdemoapp/frontend:v1.0.3 | Docker Hub |
| hashicups-edge.nomad.hcl | nginx:alpine | Docker Hub |
| hashicups.nomad.hcl | hashicorpdemoapp/product-api-db:v0.0.20 | Docker Hub |
| hashicups.nomad.hcl | hashicorpdemoapp/product-api:v0.0.21 | Docker Hub |

### Other Repositories Analyzed (No Job Specs Found)

The following repositories were analyzed but contain no .nomad.hcl job
specification files:

- **learn-nomad-cluster-setup** - Cluster setup tutorials (infrastructure configuration only)
- **learn-nomad-migrate-java** - Java application migration guide
- **learn-nomad-external-alb** - External load balancer integration
- **learn-nomad-jobspec** - Job specification documentation/examples
- **learn-nomad-sd** - Service discovery tutorials
- **learn-nomad-gs-pytechco** - Get Started application source code (no job specs, contains application code only)

## Container Registry Summary

Based on analysis of HashiCorp Nomad tutorial repositories:

### Docker Hub (hub.docker.com)

- **Official Images**: redis, nginx, postgres
- **HashiCorp Demo Apps**: hashicorpdemoapp/* (product-api, payments, public-api, frontend, product-api-db)
- **HashiCorp Tools**: hashicorp/nomad-autoscaler

### GitHub Container Registry (ghcr.io)

- **HashiCorp Education Custom Apps**: ghcr.io/hashicorp-education/learn-nomad-getting-started/*
  - ptc-setup:1.0
  - ptc-web:1.0
  - ptc-employee:1.0

## Key Findings

1. **Primary Registry**: Docker Hub is the dominant container registry used across Nomad tutorials
2. **Demo Application Pattern**: The HashiCups demo application uses the `hashicorpdemoapp/*` namespace on Docker Hub
3. **Tutorial-Specific Images**: Custom tutorial applications use GitHub Container Registry with the pattern `ghcr.io/hashicorp-education/{repo-name}/{app-name}:{version}`
4. **Infrastructure Components**: Standard infrastructure (Redis, Nginx, Postgres) uses official Docker Hub images
5. **HashiCorp Tools**: HashiCorp's own tools (nomad-autoscaler) are published to Docker Hub under the `hashicorp/*` namespace
