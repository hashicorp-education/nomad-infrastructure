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
    Name     = "${var.project_name}-server-${count.index + 1}"
    Owner    = var.owner
    AutoJoinRole     = "server"
    Hostname = "${var.project_name}-server-${count.index + 1}"
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
    Name     = "${var.project_name}-client-${count.index + 1}"
    Owner    = var.owner
    AutoJoinRole     = "client"
    Hostname = "${var.project_name}-client-${count.index + 1}"
  }
}

# Wait for instances to be ready
resource "null_resource" "wait_for_instances" {
  depends_on = [
    aws_instance.servers,
    aws_instance.clients
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
        ip       = instance.public_ip
        private_ip = instance.private_ip
      }
    }
    clients = {
      for idx, instance in aws_instance.clients :
      instance.tags.Name => {
        ip       = instance.public_ip
        private_ip = instance.private_ip
      }
    }
    ssh_user = var.ssh_user
  })
  
  filename = "${path.module}/../../ansible/inventory.ini"
}