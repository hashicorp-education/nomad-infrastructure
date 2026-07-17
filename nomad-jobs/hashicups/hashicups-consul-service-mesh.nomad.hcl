# HashiCups — Consul service mesh variant
#
# All six services run with network.mode = "bridge" and Connect sidecar proxies.
# Services communicate exclusively through mTLS Envoy sidecars using explicit
# `upstreams` blocks — transparent proxy is NOT used (consul-cni not installed).
#
# Prerequisites before running this job:
#   1. Apply service-defaults for all services:
#        consul config write nomad-jobs/consul-mesh/service-defaults/nginx.hcl
#        consul config write nomad-jobs/consul-mesh/service-defaults/frontend.hcl
#        consul config write nomad-jobs/consul-mesh/service-defaults/public-api.hcl
#        consul config write nomad-jobs/consul-mesh/service-defaults/product-api.hcl
#        consul config write nomad-jobs/consul-mesh/service-defaults/payments-api.hcl
#        consul config write nomad-jobs/consul-mesh/service-defaults/database.hcl
#   2. Apply intentions:
#        consul config write nomad-jobs/consul-mesh/intentions/nginx.hcl
#        consul config write nomad-jobs/consul-mesh/intentions/frontend.hcl
#        consul config write nomad-jobs/consul-mesh/intentions/public-api.hcl
#        consul config write nomad-jobs/consul-mesh/intentions/product-api.hcl
#        consul config write nomad-jobs/consul-mesh/intentions/payments-api.hcl
#        consul config write nomad-jobs/consul-mesh/intentions/database.hcl
#   3. Deploy and verify the API Gateway (see nomad-jobs/consul-mesh/README.md).
#
# Run:
#   nomad job run nomad-jobs/hashicups/hashicups-consul-service-mesh.nomad.hcl

#-------------------------------------------------------------------------------
# Job Variables
#-------------------------------------------------------------------------------

variable "datacenters" {
  description = "A list of datacenters in the region which are eligible for task placement."
  type        = list(string)
  default     = ["*"]
}

variable "region" {
  description = "The region where the job should be placed."
  type        = string
  default     = "global"
}

variable "frontend_version" {
  description = "Docker version tag"
  default = "v1.0.9"
}

variable "public_api_version" {
  description = "Docker version tag"
  default = "v0.0.7"
}

variable "payments_version" {
  description = "Docker version tag"
  default = "v0.0.16"
}

variable "product_api_version" {
  description = "Docker version tag"
  default = "v0.0.22"
}

variable "product_api_db_version" {
  description = "Docker version tag"
  default = "v0.0.22"
}

variable "postgres_db" {
  description = "Postgres DB name"
  default = "products"
}

variable "postgres_user" {
  description = "Postgres DB User"
  default = "postgres"
}

variable "postgres_password" {
  description = "Postgres DB Password"
  default = "password"
}

# In-mesh (bridge-network local) ports. Not exposed to the host or the internet.
variable "product_api_port" {
  description = "Product API in-mesh port"
  default     = 9090
}

variable "frontend_port" {
  description = "Frontend in-mesh port"
  default     = 3000
}

variable "payments_api_port" {
  description = "Payments API in-mesh port"
  default     = 8080
}

variable "public_api_port" {
  description = "Public API in-mesh port"
  default     = 8081
}

variable "db_port" {
  description = "Postgres in-mesh port"
  default     = 5432
}

# nginx listens on plain HTTP inside the mesh — TLS termination is handled by
# the Consul API Gateway upstream of it. Port 443 is no longer used.
variable "nginx_port" {
  description = "nginx in-mesh HTTP port (plain HTTP, no TLS — API Gateway terminates TLS)"
  default     = 8080
}

### ----------------------------------------------------------------------------
###  Job "hashicups-mesh"
### ----------------------------------------------------------------------------

job "hashicups-mesh" {
  type        = "service"
  region      = var.region
  datacenters = var.datacenters

  ## ---------------------------------------------------------------------------
  ##  Group "Database"
  ## ---------------------------------------------------------------------------

  group "db" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "database"
      port     = "${var.db_port}"
      provider = "consul"

      connect {
        sidecar_service {}
      }

      check {
        name      = "Database ready"
        type      = "script"
        command   = "/usr/bin/pg_isready"
        args      = ["-d", "${var.db_port}"]
        interval  = "5s"
        timeout   = "2s"
        on_update = "ignore_warnings"
        task      = "db"
      }
    }

    task "db" {
      driver = "docker"

      meta {
        service = "database"
      }

      config {
        image = "hashicorpdemoapp/product-api-db:${var.product_api_db_version}"
      }

      env {
        POSTGRES_DB       = var.postgres_db
        POSTGRES_USER     = var.postgres_user
        POSTGRES_PASSWORD = var.postgres_password
      }
    }
  }

  ## ---------------------------------------------------------------------------
  ##  Group "Product API"
  ## ---------------------------------------------------------------------------

  group "product-api" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "product-api"
      port     = "${var.product_api_port}"
      provider = "consul"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "database"
              local_bind_port  = var.db_port
            }
          }
        }
      }

      check {
        name     = "DB connection ready"
        type     = "http"
        path     = "/health/readyz"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }

      check {
        name     = "Product API ready"
        type     = "http"
        path     = "/health/livez"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "product-api" {
      driver = "docker"

      meta {
        service = "product-api"
      }

      config {
        image = "hashicorpdemoapp/product-api:${var.product_api_version}"
      }

      env {
        # Reaches database through the local Envoy sidecar upstream.
        DB_CONNECTION = "host=127.0.0.1 port=${var.db_port} user=${var.postgres_user} password=${var.postgres_password} dbname=${var.postgres_db} sslmode=disable"
        BIND_ADDRESS  = ":${var.product_api_port}"
      }
    }
  }

  ## ---------------------------------------------------------------------------
  ##  Group "Payments API"
  ## ---------------------------------------------------------------------------

  group "payments" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "payments-api"
      port     = "${var.payments_api_port}"
      provider = "consul"

      connect {
        sidecar_service {}
      }

      check {
        name     = "Payments API ready"
        type     = "http"
        path     = "/actuator/health"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "payments-api" {
      driver = "docker"

      meta {
        service = "payments-api"
      }

      config {
        image = "hashicorpdemoapp/payments:${var.payments_version}"
        mount {
          type   = "bind"
          source = "local/application.properties"
          target = "/application.properties"
        }
      }

      template {
        data        = "server.port=${var.payments_api_port}"
        destination = "local/application.properties"
      }

      resources {
        memory = 500
      }
    }
  }

  ## ---------------------------------------------------------------------------
  ##  Group "Public API"
  ## ---------------------------------------------------------------------------

  group "public-api" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "public-api"
      port     = "${var.public_api_port}"
      provider = "consul"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "product-api"
              local_bind_port  = var.product_api_port
            }
            upstreams {
              destination_name = "payments-api"
              local_bind_port  = var.payments_api_port
            }
          }
        }
      }

      check {
        name     = "Public API ready"
        type     = "http"
        path     = "/health"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "public-api" {
      driver = "docker"

      meta {
        service = "public-api"
      }

      config {
        image = "hashicorpdemoapp/public-api:${var.public_api_version}"
      }

      env {
        BIND_ADDRESS    = ":${var.public_api_port}"
        # Reaches product-api and payments-api through local Envoy sidecar upstreams.
        PRODUCT_API_URI = "http://127.0.0.1:${var.product_api_port}"
        PAYMENT_API_URI = "http://127.0.0.1:${var.payments_api_port}"
      }
    }
  }

  ## ---------------------------------------------------------------------------
  ##  Group "Frontend"
  ## ---------------------------------------------------------------------------

  group "frontend" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "frontend"
      port     = "${var.frontend_port}"
      provider = "consul"

      connect {
        sidecar_service {}
      }

      check {
        name     = "Frontend ready"
        type     = "http"
        path     = "/"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "frontend" {
      driver = "docker"

      meta {
        service = "frontend"
      }

      config {
        image = "hashicorpdemoapp/frontend:${var.frontend_version}"
      }

      env {
        # /api calls route through nginx's sidecar upstream, which proxies to public-api.
        NEXT_PUBLIC_PUBLIC_API_URL = "/"
        NEXT_PUBLIC_FOOTER_FLAG    = "Frontend instance ${NOMAD_ALLOC_INDEX}"
        PORT                       = "${var.frontend_port}"
      }
    }
  }

  ## ---------------------------------------------------------------------------
  ##  Group "NGINX"
  ##
  ##  In the mesh variant nginx listens on plain HTTP (not HTTPS) because TLS
  ##  is terminated by the Consul API Gateway. The nginx-tls-init prestart task
  ##  and static port 443 from the service-discovery variant are removed.
  ## ---------------------------------------------------------------------------

  group "nginx" {
    count          = 1
    shutdown_delay = "10s"

    network {
      mode = "bridge"
    }

    service {
      name     = "nginx"
      port     = "${var.nginx_port}"
      provider = "consul"

      connect {
        sidecar_service {
          proxy {
            upstreams {
              destination_name = "frontend"
              local_bind_port  = var.frontend_port
            }
            upstreams {
              destination_name = "public-api"
              local_bind_port  = var.public_api_port
            }
          }
        }
      }

      check {
        name     = "NGINX ready"
        type     = "http"
        path     = "/health"
        interval = "5s"
        timeout  = "5s"
        expose   = true
      }
    }

    task "nginx" {
      driver = "docker"

      meta {
        service = "nginx-mesh-reverse-proxy"
      }

      config {
        image = "nginx:alpine"
        mount {
          type   = "bind"
          source = "local/default.conf"
          target = "/etc/nginx/conf.d/default.conf"
        }
      }

      template {
        data = <<EOF
proxy_cache_path /var/cache/nginx levels=1:2 keys_zone=STATIC:10m inactive=7d use_temp_path=off;

server {
  listen ${var.nginx_port};
  server_name _;
  server_tokens off;
  gzip on;
  gzip_proxied any;
  gzip_comp_level 4;
  gzip_types text/css application/javascript image/svg+xml;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection 'upgrade';
  proxy_set_header Host $host;
  proxy_cache_bypass $http_upgrade;

  # Routes to frontend through the local Envoy sidecar upstream.
  location / {
    proxy_pass http://127.0.0.1:${var.frontend_port};
  }

  # Routes to public-api through the local Envoy sidecar upstream.
  location /api {
    proxy_pass http://127.0.0.1:${var.public_api_port};
  }

  location = /health {
    access_log off;
    add_header 'Content-Type' 'application/json';
    return 200 '{"status":"UP"}';
  }
}
EOF
        destination = "local/default.conf"
      }
    }
  }
}
