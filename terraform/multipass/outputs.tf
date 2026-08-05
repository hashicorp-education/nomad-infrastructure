# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
output "server_ips" {
  description = "IPv4 addresses of server VMs"
  value       = { for instance in multipass_instance.servers : instance.name => instance.ipv4 }
}

output "client_ips" {
  description = "IPv4 addresses of every client VM, internal and ingress"
  value = merge(
    { for instance in multipass_instance.clients : instance.name => instance.ipv4 },
    { for instance in multipass_instance.ingress_clients : instance.name => instance.ipv4 }
  )
}

output "ingress_client_ips" {
  description = "IPv4 addresses of the dedicated ingress client VM(s) (Option E's API Gateway)"
  value       = { for instance in multipass_instance.ingress_clients : instance.name => instance.ipv4 }
}

output "consul_ui_urls" {
  description = "URLs to access Consul UI on servers (TLS enabled by default)"
  value       = [for instance in multipass_instance.servers : "https://${instance.ipv4}:8443"]
}

output "nomad_ui_urls" {
  description = "URLs to access Nomad UI on servers (TLS enabled by default)"
  value       = [for instance in multipass_instance.servers : "https://${instance.ipv4}:4646"]
}

output "ssh_instructions" {
  description = "SSH commands to access instances"
  value       = <<-EOT
    ==========================================
    SSH Access Instructions
    ==========================================

    SSH Private Key: ${var.ssh_private_key_path}

    Servers:
    %{for instance in multipass_instance.servers~}
      ssh -o 'IdentitiesOnly=yes' -i ${var.ssh_private_key_path} ${var.ssh_user}@${instance.ipv4}  # ${instance.name}
    %{endfor~}

    Clients:
    %{for instance in multipass_instance.clients~}
      ssh -o 'IdentitiesOnly=yes' -i ${var.ssh_private_key_path} ${var.ssh_user}@${instance.ipv4}  # ${instance.name}
    %{endfor~}
    %{for instance in multipass_instance.ingress_clients~}
      ssh -o 'IdentitiesOnly=yes' -i ${var.ssh_private_key_path} ${var.ssh_user}@${instance.ipv4}  # ${instance.name}
    %{endfor~}
  EOT
}
