# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Nomad/Consul Server Instances
resource "aws_instance" "servers" {
  count                  = var.server_count
  ami                    = data.aws_ami.chosen_ami.id
  instance_type          = var.server_instance_type
  key_name               = aws_key_pair.nomad_consul_key.key_name
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.nomad_consul_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  # Enforce IMDSv2 to block SSRF credential-theft via Consul HTTP service checks.
  # With http_tokens = "required", GET requests to 169.254.169.254 return 401
  # because no session token is present; only PUT-then-GET (the IMDSv2 flow)
  # is accepted.  http_put_response_hop_limit = 1 prevents containers from
  # reaching the metadata service through the host network stack.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name         = "${var.project_name}-server-${count.index + 1}"
    Owner        = var.owner
    AutoJoinRole = "server"
    Hostname     = "${var.project_name}-server-${count.index + 1}"
  }
}

# Nomad Client Instances
resource "aws_instance" "clients" {
  count                  = var.client_count
  ami                    = data.aws_ami.chosen_ami.id
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.nomad_consul_key.key_name
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.nomad_consul_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  # Enforce IMDSv2 — same reasoning as aws_instance.servers above.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name         = "${var.project_name}-client-${count.index + 1}"
    Owner        = var.owner
    AutoJoinRole = "client"
    Hostname     = "${var.project_name}-client-${count.index + 1}"
  }
}

# Dedicated public ingress client(s) — runs the Consul API Gateway (Option E)
# so app-facing ports don't need to be open on every Nomad client. Same
# AutoJoinRole as aws_instance.clients (Consul/Nomad server retry_join
# matches on this tag, not on instance identity), but with an extra security
# group (ingress_sg) attached. See _context/wiki/dedicated-ingress-node-plan.md.
resource "aws_instance" "ingress_clients" {
  count                  = var.ingress_client_count
  ami                    = data.aws_ami.chosen_ami.id
  instance_type          = var.client_instance_type
  key_name               = aws_key_pair.nomad_consul_key.key_name
  subnet_id              = aws_subnet.subnet.id
  vpc_security_group_ids = [aws_security_group.nomad_consul_sg.id, aws_security_group.ingress_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  # Enforce IMDSv2 — same reasoning as aws_instance.servers above.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name         = "${var.project_name}-ingress-client-${count.index + 1}"
    Owner        = var.owner
    AutoJoinRole = "client"
    Hostname     = "${var.project_name}-ingress-client-${count.index + 1}"
  }
}

# Wait for instances to be ready
resource "null_resource" "wait_for_instances" {
  depends_on = [
    aws_instance.servers,
    aws_instance.clients,
    aws_instance.ingress_clients
  ]

  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Generate Ansible Inventory
resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.wait_for_instances]

  content = templatefile("${path.module}/inventory.tpl", {
    servers = {
      for idx, instance in aws_instance.servers :
      instance.tags.Name => {
        ip         = instance.public_ip
        private_ip = instance.private_ip
      }
    }
    # Merges the regular (internal) and dedicated ingress clients into one
    # map so both land in the same Ansible [clients] group — see
    # inventory.tpl and _context/wiki/dedicated-ingress-node-plan.md. The
    # `role` field becomes each host's nomad_node_role inventory var, which
    # ansible/roles/nomad's nomad_client_meta default reads to render
    # Nomad's client meta.nodeRole — the attribute api-gateway.nomad.hcl's
    # constraint matches on.
    clients = merge(
      {
        for idx, instance in aws_instance.clients :
        instance.tags.Name => {
          ip         = instance.public_ip
          private_ip = instance.private_ip
          role       = "internal"
        }
      },
      {
        for idx, instance in aws_instance.ingress_clients :
        instance.tags.Name => {
          ip         = instance.public_ip
          private_ip = instance.private_ip
          role       = "ingress"
        }
      }
    )
    ssh_user = var.ssh_user
  })

  filename = "${path.module}/../../ansible/inventory.ini"
}