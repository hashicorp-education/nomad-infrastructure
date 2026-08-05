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

variable "deployment_platform" {
  description = "Set to \"aws\" so countdash-web's service-catalog entry registers the EC2 public hostname (externally reachable) instead of the private IP. Defaults to \"generic\", which uses attr.unique.network.ip-address - correct for Multipass, and for AWS internal-only access, but not externally reachable on AWS. Shared across every job spec in this repo that needs this fallback (this file, countdash-consul-service-discovery.nomad.hcl, hashicups-multipass.nomad.hcl) - set it once via NOMAD_VAR_deployment_platform (see ansible/set-cluster-env.sh, which detects the platform from inventory.ini and exports this automatically) rather than passing -var by hand on every job run."
  default = "generic"
}

job "countdash-nomad-sd" {

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
      # attr.unique.network.ip-address is the platform-agnostic node attribute
      # Nomad fingerprints on every host (AWS, Multipass, bare metal, ...).
      # attr.unique.platform.aws.local-ipv4 only fingerprints on AWS via the
      # EC2 metadata service and is absent on Multipass VMs.
      address  = attr.unique.network.ip-address

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

    network {
      port "countdash-web" {
        static = var.countdash-web-port
      }
    }

    service {
      name = "countdash-web"
      provider = "nomad"
      port = "countdash-web"
      # attr.unique.network.ip-address is the platform-agnostic node attribute
      # Nomad fingerprints on every host - correct as-is on Multipass (no
      # public/private split; the single bridged NIC IP is already reachable
      # from the host machine's browser). On AWS this resolves to the
      # *private* IP, so set var.deployment_platform=aws to register the
      # public hostname instead (only fingerprinted on AWS via the EC2
      # metadata service). Don't pass -var by hand for this - source
      # ansible/set-cluster-env.sh, which detects the platform from
      # inventory.ini and exports NOMAD_VAR_deployment_platform automatically
      # (Nomad's CLI reads NOMAD_VAR_<name> exactly like -var <name>=value).
      #
      # WHY THIS IS var.* AND NOT meta.* OR attr.* AS THE CONDITION - confirmed
      # by live testing, not assumed: this ternary's *condition* must be a
      # var.* value, known at job-submission time, before any node is chosen.
      # Tried making this fully automatic with no var at all, using node-level
      # attr.*/meta.* as the condition instead (so Ansible-set node metadata
      # could drive it with zero job-spec input) - both silently resolved to
      # the wrong (private-IP) branch with NO error, even when the referenced
      # attribute/meta genuinely existed and was true on that exact node
      # (confirmed via a passing `constraint` block on the identical
      # attribute/meta as a control test). Each ternary *branch* (the two
      # possible address values) IS resolved per-node at runtime against
      # whatever node the allocation lands on - it's specifically the
      # *condition* that must be parse-time-known. If the selected branch's
      # attribute doesn't exist on that node (e.g. deployment_platform=aws
      # run against non-AWS infra), Nomad does NOT error - it silently
      # registers the literal, unresolved text
      # "${attr.unique.platform.aws.public-hostname}" as the service address,
      # which then fails the check below trying to parse that literal text
      # as a URL. If you see that, deployment_platform doesn't match the
      # platform you're actually deploying to - fix the var/env, not the job
      # spec.
      address  = var.deployment_platform == "aws" ? attr.unique.platform.aws.public-hostname : attr.unique.network.ip-address

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
        image          = "hashicorpdev/counter-dashboard:${var.countdash-web-version}-${attr.cpu.arch}"
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
