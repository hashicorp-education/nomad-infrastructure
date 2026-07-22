# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

# Cloud-init user-data: appends the user's existing SSH public key to the
# default 'ubuntu' user Multipass's Ubuntu images already create. Same
# content for every VM - no per-node customization needed.
resource "local_file" "cloudinit" {
  content = templatefile("${path.module}/cloudinit.yaml.tpl", {
    ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  })
  filename = "${path.module}/.generated/cloudinit.yaml"
}

# Nomad/Consul server VMs
resource "multipass_instance" "servers" {
  count          = var.server_count
  name           = "${var.project_name}-server-${count.index + 1}"
  cpus           = var.vm_cpus
  memory         = var.vm_memory
  disk           = var.vm_disk
  image          = var.vm_image
  cloudinit_file = local_file.cloudinit.filename
}

# Nomad client VMs
resource "multipass_instance" "clients" {
  count          = var.client_count
  name           = "${var.project_name}-client-${count.index + 1}"
  cpus           = var.vm_cpus
  memory         = var.vm_memory
  disk           = var.vm_disk
  image          = var.vm_image
  cloudinit_file = local_file.cloudinit.filename
}

# Generate Ansible inventory - written to ansible/inventory.ini, the same
# path used by ../aws/. Run AWS or Multipass, never both at once: applying
# this resource overwrites whichever inventory.ini is currently there (and
# with it, which cluster `ansible/tokens/` and `ansible/.tls/` describe).
# Switching back to AWS just means re-running `terraform apply` in ../aws/
# to regenerate its inventory.ini again. This also means teardown.yaml and
# every other playbook work unmodified against either environment - they
# just need `-i inventory.ini` for whichever cluster is currently live.
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    servers = {
      for idx, instance in multipass_instance.servers :
      instance.name => { ip = instance.ipv4 }
    }
    clients = {
      for idx, instance in multipass_instance.clients :
      instance.name => { ip = instance.ipv4 }
    }
    ssh_user             = var.ssh_user
    ssh_private_key_path = pathexpand(var.ssh_private_key_path)
  })

  filename = "${path.module}/../../ansible/inventory.ini"
}
