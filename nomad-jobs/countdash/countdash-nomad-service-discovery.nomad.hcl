variable "countdash-api-port" {
  description = "Countdash API Port"
  default = 9001
}
variable "countdash-web-port" {
  description = "Countdash web port"
  default = 9002
}

job "countdash" {

  group "countdash-api" {
    count = 1

    network {
      port "countdash-api" {
        static = var.countdash-api-port
      }
    }

    service {
      name = "countdash-api"
      provider = "nomad"
      port = "countdash-api"      
      address  = attr.unique.platform.aws.local-ipv4

      check {
        name      = "Countdash API ready" 
        type      = "http"
        path      = "/actuator/health"
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
        image = "hashicorpdev/counter-api:v3"
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

    network {
      port "countdash-web" {
        static = var.countdash-web-port
      }
    }

    service {
      name = "countdash-web"
      provider = "nomad"
      port = "countdash-web"
      address  = attr.unique.platform.aws.public-hostname

      check {
        name      = "Countdash web ready"
        type      = "http"
        path      = "/"
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
        PORT="${var.countdash-web-port}"
      }

      config {
        image          = "hashicorpdev/counter-dashboard:v3"
        auth_soft_fail = true
        ports = ["countdash-web"]
      }

      template {
        data = <<EOH
        BIND_ADDRESS = ":${var.countdash-api-port}"
{{ range nomadService "countdash-api" }}
COUNTING_SERVICE_URL = "http://{{ .Address }}:{{ .Port }}"
{{ end }}
EOH
        destination = "local/env.txt"
        env         = true
      }
    }
  }
}
