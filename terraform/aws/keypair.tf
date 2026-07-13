# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Generate SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create AWS key pair using the generated public key
resource "aws_key_pair" "nomad_consul_key" {
  key_name   = "${var.project_name}-key-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  public_key = tls_private_key.ssh_key.public_key_openssh

  tags = {
    Name  = "${var.project_name}-key"
    Owner = var.owner
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      key_name,  # Ignore changes to key_name to prevent recreation on every apply
    ]
  }
}

# Save private key locally for Ansible
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ssh_key.private_key_pem
  filename        = "${path.module}/../../ansible/ssh_key.pem"
  file_permission = "0600"
}

# Save public key locally for reference
resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "${path.module}/../../ansible/ssh_key.pub"
}

# Ensure correct permissions on private key (belt and suspenders approach)
resource "null_resource" "fix_key_permissions" {
  depends_on = [local_sensitive_file.private_key]

  provisioner "local-exec" {
    command = "chmod 600 ${path.module}/../../ansible/ssh_key.pem"
  }

  triggers = {
    key_content = tls_private_key.ssh_key.private_key_pem
  }
}