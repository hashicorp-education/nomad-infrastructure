# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
output "ami_id" {
  value = data.aws_ami.chosen_ami.id
}

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.nomad_consul_vpc.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.subnet.id
}

output "security_group_id" {
  description = "ID of the security group"
  value       = aws_security_group.nomad_consul_sg.id
}

output "server_public_ips" {
  description = "Public IP addresses of server instances"
  value       = aws_instance.servers[*].public_ip
}

output "server_private_ips" {
  description = "Private IP addresses of server instances"
  value       = aws_instance.servers[*].private_ip
}

output "client_public_ips" {
  description = "Public IP addresses of internal (non-ingress) client instances. See client_public_ips_by_node for a version that also includes the dedicated ingress client(s)."
  value       = aws_instance.clients[*].public_ip
}

output "client_private_ips" {
  description = "Private IP addresses of internal (non-ingress) client instances."
  value       = aws_instance.clients[*].private_ip
}

output "ingress_client_public_ips" {
  description = "Public IP addresses of the dedicated public ingress client instance(s) — runs the Consul API Gateway for Option E. See _context/wiki/dedicated-ingress-node-plan.md."
  value       = aws_instance.ingress_clients[*].public_ip
}

output "server_public_ips_by_node" {
  description = "Public IP addresses of server instances, keyed by the Nomad node name Ansible assigns (nomad-server-N). Avoids cross-referencing the private IP Nomad reports (e.g. via `nomad node status` or a job's service-catalog address) against the parallel server_public_ips/server_private_ips lists by index - look up the node name directly instead."
  value = {
    for idx, instance in aws_instance.servers :
    "nomad-server-${idx + 1}" => instance.public_ip
  }
}

output "client_public_ips_by_node" {
  description = "Public IP addresses of all client instances (internal and dedicated ingress), keyed by node name. Internal clients use the Nomad node name Ansible assigns (nomad-client-N); the dedicated ingress client (see _context/wiki/dedicated-ingress-node-plan.md) is keyed nomad-ingress-client-N to distinguish it — that's the one running the Consul API Gateway for Option E. Same rationale as server_public_ips_by_node - useful for finding the externally-reachable address of a job allocation once you know which client node it landed on."
  value = merge(
    {
      for idx, instance in aws_instance.clients :
      "nomad-client-${idx + 1}" => instance.public_ip
    },
    {
      for idx, instance in aws_instance.ingress_clients :
      "nomad-ingress-client-${idx + 1}" => instance.public_ip
    }
  )
}

output "load_balancer_dns_name" {
  description = "DNS name of the external ALB (null unless enable_load_balancer is true)"
  value       = try(aws_lb.nomad_clients[0].dns_name, null)
}

output "load_balancer_url" {
  description = "URL of the external ALB, forwarding to load_balancer_target_port on every client (null unless enable_load_balancer is true)"
  value       = try("http://${aws_lb.nomad_clients[0].dns_name}", null)
}

output "consul_ui_urls" {
  description = "URLs to access Consul UI on servers (TLS enabled by default)"
  value       = [for ip in aws_instance.servers[*].public_ip : "https://${ip}:8443"]
}

output "nomad_ui_urls" {
  description = "URLs to access Nomad UI on servers (TLS enabled by default)"
  value       = [for ip in aws_instance.servers[*].public_ip : "https://${ip}:4646"]
}

output "ssh_commands" {
  description = "SSH commands to connect to instances"
  value = {
    servers         = [for idx, ip in aws_instance.servers[*].public_ip : "ssh -o 'IdentitiesOnly yes' -i ../../ansible/ssh_key.pem ${var.ssh_user}@${ip}"]
    clients         = [for idx, ip in aws_instance.clients[*].public_ip : "ssh -o 'IdentitiesOnly yes' -i ../../ansible/ssh_key.pem ${var.ssh_user}@${ip}"]
    ingress_clients = [for idx, ip in aws_instance.ingress_clients[*].public_ip : "ssh -o 'IdentitiesOnly yes' -i ../../ansible/ssh_key.pem ${var.ssh_user}@${ip}"]
  }
}

output "ssh_private_key_path" {
  description = "Path to the generated SSH private key"
  value       = local_sensitive_file.private_key.filename
}

output "ssh_public_key" {
  description = "Generated SSH public key"
  value       = tls_private_key.ssh_key.public_key_openssh
}

output "iam_role_name" {
  description = "IAM role name"
  value       = aws_iam_role.instance_role.name
}

output "iam_instance_profile_name" {
  description = "IAM instance profile name"
  value       = aws_iam_instance_profile.instance_profile.name
}
