# Consul API Gateway — Nomad job
#
# Deploys an Envoy-based Consul API Gateway in the `ingress` namespace.
# The gateway terminates HTTPS on port 8447 and routes to mesh services
# via the http-route config entries in this directory.
#
# Prerequisites:
#   1. Consul `api-gateway` and `inline-certificate` config entries applied
#      (see gateway-listener.hcl and inline-certificate.hcl).
#   2. Nomad Variable with the Consul CA cert stored:
#        nomad var put -namespace ingress \
#          nomad/jobs/api-gateway/gateway/setup \
#          consul_cacert=@ansible/.tls/ca.pem
#   3. Port 8447 open in the AWS security group — already declared in
#      terraform/aws/terraform.tfvars (extra_ingress_ports). If you haven't
#      applied that, ansible/playbooks/update-security-group.yaml (invoked
#      automatically from consul_nomad_api_gateway.yaml) opens it too; it
#      checks for an existing rule first, so running both is harmless.
#
# Run (preferred): ansible-playbook -i inventory.ini playbooks/consul_nomad_api_gateway.yaml
# Run (job only):
#   nomad job run -namespace ingress api-gateway.nomad.hcl
#
# After the allocation is running, verify:
#   nomad alloc logs -namespace ingress -task gateway <alloc-id>   # Envoy bootstrap logs
#   consul config read -kind api-gateway -name api-gateway         # gateway registered

job "api-gateway" {
  type      = "service"
  namespace = "ingress"

  group "gateway" {
    count = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"

      port "https" {
        static = 8447
        to     = 8447
      }
    }

    # The gateway task fetches the Consul CA cert from a Nomad Variable.
    # Store it before running this job:
    #   nomad var put -namespace ingress \
    #     nomad/jobs/api-gateway/gateway/setup \
    #     consul_cacert=@ansible/.tls/ca.pem

    # hashicorp/consul:2.0.1 does not bundle the envoy binary, and copying the
    # glibc-linked envoy binary from envoyproxy/envoy into the Alpine/musl-based
    # consul image fails with "Error relocating /alloc/envoy: symbol not found"
    # (musl's dynamic linker can't satisfy glibc-specific symbols). Instead, run
    # the gateway task on envoyproxy/envoy's (glibc) base image, and copy the
    # statically-linked consul Go binary into it via the shared alloc/ directory
    # — Go binaries built with CGO_ENABLED=0 have no libc dependency and run
    # unmodified on any Linux base image.
    task "fetch-consul" {
      driver = "docker"
      lifecycle {
        hook    = "prestart"
        sidecar = false
      }

      config {
        image      = "hashicorp/consul:2.0.2"
        entrypoint = ["/bin/sh", "-c"]
        args = [
          "cp \"$(command -v consul)\" /alloc/consul && chmod +x /alloc/consul",
        ]
      }

      resources {
        cpu    = 100
        memory = 128
      }
    }

    task "gateway" {
      driver = "docker"

      # Workload identity: exchanges the Nomad JWT for a Consul ACL token with
      # the builtin/api-gateway templated policy, via the binding rule created in
      # ansible/playbooks/consul_nomad_service_mesh.yaml.
      identity {
        name        = "consul_default"
        aud         = ["consul.io"]
        file        = true
        change_mode = "restart"
        ttl         = "1h"
      }

      config {
        image = "envoyproxy/envoy:v1.38.2"

        # /alloc/consul is copied in by the fetch-consul prestart task. envoy
        # is already on PATH in this image, so no -envoy-binary flag is needed.
        entrypoint = ["/bin/sh", "-c"]
        args = [
          <<-EOT
          set -e

          # Bootstrap Envoy via Consul's built-in gateway bootstrap helper.
          # consul connect envoy -gateway=api -register runs until the process exits.
          # -address must be the container's own interface IP (resolved via
          # Consul's go-sockaddr template at runtime), not NOMAD_IP_https —
          # that Nomad var is the host-side NAT-mapped address, which Envoy
          # cannot bind to from inside the container's network namespace.
          exec /alloc/consul connect envoy \
            -gateway=api \
            -register \
            -service api-gateway \
            -address '{{ GetInterfaceIP "eth0" }}:8447' \
            -token "${CONSUL_HTTP_TOKEN}"
          EOT
        ]
      }

      # Render the Consul CA cert and set environment variables.
      # CONSUL_HTTP_TOKEN is populated automatically by Consul workload identity
      # when the gateway allocation starts — no static token required.
      template {
        data        = <<-EOT
        {{- with nomadVar "nomad/jobs/api-gateway/gateway/setup" -}}
        CONSUL_CACERT=/secrets/consul-tls/ca.pem
        {{- end }}
        EOT
        destination = "secrets/consul.env"
        env         = true
      }

      # Relative to secrets/, so Nomad's docker driver bind-mounts it to
      # /secrets/consul-tls/ca.pem inside the container. An absolute
      # destination like /tmp/... is NOT bind-mounted into docker tasks.
      template {
        data        = <<-EOT
        {{- with nomadVar "nomad/jobs/api-gateway/gateway/setup" -}}
        {{ .consul_cacert }}
        {{- end }}
        EOT
        destination = "secrets/consul-tls/ca.pem"
        change_mode = "restart"
      }

      # The task runs in bridge network mode, so 127.0.0.1 refers to the
      # container's own loopback, not the host's Consul agent. Use the
      # client node's actual IP (reachable from the bridge namespace) instead.
      # CONSUL_TLS_SERVER_NAME must match the client agent cert's SAN
      # (client.<datacenter>.<domain> — this cluster's Consul domain is
      # "global", not the default "consul").
      env {
        CONSUL_HTTP_ADDR       = "https://${attr.unique.network.ip-address}:8443"
        CONSUL_GRPC_ADDR       = "https://${attr.unique.network.ip-address}:8503"
        CONSUL_TLS_SERVER_NAME = "client.dc1.global"
      }

      resources {
        cpu    = 200
        memory = 256
      }
    }
  }
}
