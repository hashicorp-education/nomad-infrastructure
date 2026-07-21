variable "countdash-api-port" {
  description = "Countdash API Port"
  default = 9001
}
variable "countdash-web-port" {
  description = "Countdash web port"
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

job "countdash-consul-sd" {

  group "countdash-api" {
    count = 1
    shutdown_delay = "10s"

    network {
      port "countdash-api" {
        static = var.countdash-api-port
      }
      dns {
        servers = ["172.17.0.1"] 
      }
    }

    service {
      name = "countdash-api"
      provider = "consul"
      port = "countdash-api"
      # attr.unique.network.ip-address is the platform-agnostic node attribute
      # Nomad fingerprints on every host (AWS, Multipass, bare metal, ...).
      # attr.unique.platform.aws.local-ipv4 only fingerprints on AWS via the
      # EC2 metadata service and is absent on Multipass VMs.
      address  = attr.unique.network.ip-address

      check {
        name     = "Countdash API ready" 
        type     = "http"
        path     = "/actuator/health"
        interval  = "5s"
                timeout   = "5s"

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
        ports = ["countdash-api"]
       mount {
          type   = "bind"
          source = "local/application.properties"
          target = "/application.properties"
        }
      }
      template {
        data = "server.port=${var.countdash-api-port}"
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
      port "countdash-web" {
        static = var.countdash-web-port
      }
      dns {
        servers = ["172.17.0.1"] 
      }
    }

    service {
      name = "countdash-web"
      provider = "consul"
      port = "countdash-web"
      # attr.unique.network.ip-address is the platform-agnostic node attribute
      # Nomad fingerprints on every host. attr.unique.platform.aws.public-hostname
      # only fingerprints on AWS and is absent on Multipass VMs; Multipass has
      # no public/private split anyway - the single bridged NIC IP is already
      # reachable from the host machine's browser.
      address  = attr.unique.network.ip-address
      check {
        name      = "Countdash web ready"
        type      = "http"
        path            = "/"
        interval  = "5s"
        timeout   = "5s"
      }
    }

    task "countdash-web" {
      driver = "docker"

      meta {
        service = "countdash-web"
      }
      env {
        COUNTING_SERVICE_URL = "http://countdash-api.service.dc1.global:${var.countdash-api-port}"
        PORT="${var.countdash-web-port}"
      }

      config {
        image          = "hashicorpdev/counter-dashboard:${var.countdash-web-version}-${attr.cpu.arch}"
        auth_soft_fail = true
        ports = ["countdash-web"]
      }
    }
  }
}
