# Countdash — Consul service mesh, transparent proxy variant (default mesh
# mode for Countdash as of this file's "make it default" follow-up)
#
# Live-verified end-to-end on a real AWS cluster (Consul v2.0.1, Nomad
# v2.0.4) — see _context/wiki/transparent-proxy-enablement-plan.md for the
# full rollout, including four real bugs found and fixed along the way, plus
# a later follow-up that automated away the two manual steps this header
# used to document (Nomad client restart, gateway ACL policy) — both are
# now handled automatically by consul_nomad_service_mesh.yaml.
#
# Same app and same mesh (network.mode = "bridge", Connect sidecars) as
# countdash-upstreams.nomad.hcl (still available as the explicit-upstreams
# alternative — see nomad-jobs/consul-mesh/README.md Step 7b), but the
# countdash-web -> countdash-api hop uses Consul's transparent_proxy instead
# of an explicit `upstreams` block: countdash-web calls Consul's virtual-IP
# DNS name and the Envoy sidecar intercepts the connection via iptables
# rules installed by the consul-cni CNI plugin, rather than countdash-web
# calling a fixed 127.0.0.1 bind port.
#
# This is a separate file, not a modified
# countdash-upstreams.nomad.hcl, per this repo's
# convention of shipping mesh variants as new files (see
# nomad-jobs/consul-mesh/README.md). The job ID is also unique
# (countdash-mesh-tproxy, not countdash-mesh-upstreams) to avoid the job-ID
# collision bug already hit twice in this repo — see
# _context/wiki/countdash-job-id-collision-and-multiarch.md.
#
# Prerequisites beyond the base countdash-upstreams.nomad.hcl
# mesh setup (Consul Connect enabled, ingress namespace, API Gateway) — both
# handled automatically by running consul_nomad_service_mesh.yaml, no manual
# steps required:
#   1. consul-cni plugin installed on Nomad clients — this is NOT part of
#      the base Option E rollout. Requires consul_nomad_service_mesh.yaml
#      Play 2 (consul_cni_enabled: true is already the default there). If a
#      new consul-cni binary is actually installed on a client where Nomad
#      is already running, a play-level Ansible handler restarts Nomad on
#      that client automatically — Nomad only fingerprints /opt/cni/bin for
#      new plugins at agent startup, not on a timer, so this used to require
#      a manual `systemctl restart nomad`; live-reverified it no longer
#      does.
#   2. Same service-defaults + intentions as the non-transparent variant
#      (countdash-web -> countdash-api, api-gateway -> countdash-web) —
#      intentions authorize by service name regardless of upstream mode, so
#      no new Consul config entries are needed if the base mesh job specs
#      already deployed once.
#
# See _context/wiki/transparent-proxy-enablement-plan.md for two more
# prerequisites this repo's tooling didn't originally handle (fixed there,
# not here): the consul_nomad_service_mesh.yaml DNS-ACL-token regression
# (Bug 2), and why COUNTING_SERVICE_URL below uses the *.virtual.<domain>
# DNS name rather than the classic *.service.<datacenter>.<domain> name
# used elsewhere in this repo (Bug 3).
#
# Run:
#   nomad job run nomad-jobs/consul-mesh/countdash-transparent-proxy.nomad.hcl

variable "countdash-api-port" {
  description = "Local (in-mesh) port the countdash-api task listens on. Not exposed to the host."
  default = 9001
}
variable "countdash-web-port" {
  description = "Local (in-mesh) port the countdash-web task listens on. Not exposed to the host — reached only through the Consul API Gateway (see nomad-jobs/consul-mesh/)."
  default = 9002
}

variable "countdash-api-version" {
  description = "Countdash API image tag prefix. The CPU architecture suffix (amd64/arm64) is appended automatically at task-start time via $${attr.cpu.arch} interpolation, matching HashiCorp's published hashicorpdev/counter-api:v3-amd64 / v3-arm64 tags."
  default = "v3"
}

variable "countdash-web-version" {
  description = "Countdash web image tag prefix. The CPU architecture suffix (amd64/arm64) is appended automatically at task-start time via $${attr.cpu.arch} interpolation, matching HashiCorp's published hashicorpdev/counter-dashboard:v3-amd64 / v3-arm64 tags."
  default = "v3"
}

job "countdash-mesh-tproxy" {

  group "countdash-api" {
    count = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "countdash-api"
      port     = "${var.countdash-api-port}"
      provider = "consul"

      connect {
        sidecar_service {}
      }

      check {
        name     = "Countdash API ready"
        type     = "http"
        path     = "/actuator/health"
        interval = "5s"
        timeout  = "5s"
        expose   = true

        check_restart {
          limit = 0
        }
      }
    }

    task "countdash-api" {
      driver = "docker"

      meta {
        service = "countdash-api"
      }

      config {
        image = "hashicorpdev/counter-api:${var.countdash-api-version}-${attr.cpu.arch}"
        mount {
          type   = "bind"
          source = "local/application.properties"
          target = "/application.properties"
        }
      }
      template {
        data        = "server.port=${var.countdash-api-port}"
        destination = "local/application.properties"
      }
      resources {
        memory = 500
      }
    }
  }

  group "countdash-web" {
    count = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "countdash-web"
      port     = "${var.countdash-web-port}"
      provider = "consul"

      # Transparent proxy instead of an explicit upstreams block: no local
      # bind port is declared here. Requires the consul-cni plugin on the
      # placing Nomad client (see header comment).
      connect {
        sidecar_service {
          proxy {
            transparent_proxy {}
          }
        }
      }

      check {
        name     = "Countdash web ready"
        type     = "http"
        path     = "/"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "countdash-web" {
      driver = "docker"

      meta {
        service = "countdash-web"
      }
      env {
        # Must use Consul's *virtual-IP* DNS name (<service>.virtual.<domain>),
        # not the classic <service>.service.<datacenter>.<domain> name used by
        # nomad-jobs/consul-sd/*.hcl. consul-cni's iptables rules only
        # intercept traffic destined to a Consul virtual IP (240.0.0.0/8);
        # the classic catalog-DNS name resolves to the real backing address,
        # which bypasses the mesh entirely and connects direct (getting
        # refused, since the destination port isn't exposed on the host).
        # Confirmed live: `dig countdash-api.virtual.global` -> 240.0.0.1,
        # vs. `dig countdash-api.service.dc1.global` -> the real node IP.
        COUNTING_SERVICE_URL = "http://countdash-api.virtual.global:${var.countdash-api-port}"
        PORT                 = "${var.countdash-web-port}"
      }

      config {
        image          = "hashicorpdev/counter-dashboard:${var.countdash-web-version}-${attr.cpu.arch}"
        auth_soft_fail = true
      }
    }
  }
}
