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
  description = "Public IP addresses of client instances"
  value       = aws_instance.clients[*].public_ip
}

output "client_private_ips" {
  description = "Private IP addresses of client instances"
  value       = aws_instance.clients[*].private_ip
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
    servers = [for idx, ip in aws_instance.servers[*].public_ip : "ssh -o 'IdentitiesOnly yes' -i ../../ansible/ssh_key.pem ${var.ssh_user}@${ip}"]
    clients = [for idx, ip in aws_instance.clients[*].public_ip : "ssh -o 'IdentitiesOnly yes' -i ../../ansible/ssh_key.pem ${var.ssh_user}@${ip}"]
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
  value = aws_iam_instance_profile.instance_profile.name
}
