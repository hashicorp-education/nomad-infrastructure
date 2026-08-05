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

job "countdash-mesh-upstreams" {

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

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "countdash-api"
              local_bind_port  = var.countdash-api-port
            }
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
        # Reaches countdash-api through the local Envoy sidecar upstream
        # instead of Consul DNS — this is the mesh-native replacement for the
        # countdash-consul-service-discovery variant's countdash-api.service.dc1.global lookup.
        COUNTING_SERVICE_URL = "http://127.0.0.1:${var.countdash-api-port}"
        PORT                 = "${var.countdash-web-port}"
      }

      config {
        image          = "hashicorpdev/counter-dashboard:${var.countdash-web-version}-${attr.cpu.arch}"
        auth_soft_fail = true
      }
    }
  }
}
