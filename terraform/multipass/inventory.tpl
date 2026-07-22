# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
[servers]
%{ for name, instance in servers ~}
${name} ansible_host=${instance.ip} private_ip=${instance.ip}
%{ endfor ~}

[clients]
%{ for name, instance in clients ~}
${name} ansible_host=${instance.ip} private_ip=${instance.ip} nomad_node_role=${instance.role}
%{ endfor ~}

[all:vars]
ansible_user=${ssh_user}
ansible_ssh_private_key_file=${ssh_private_key_path}
ansible_python_interpreter=/usr/bin/python3
# Multipass has no AWS EC2 API to auto-join against - fall back to the
# consul role's static-IP retry_join. Nomad already defaults to this
# (nomad_cloud_auto_join_enabled: false) so no matching var is needed there.
consul_use_aws_cloud_join=false
# dnsmasq's default upstream resolver (169.254.169.253) is the AWS VPC
# resolver and is unreachable outside AWS. Override with public resolvers
# so dnsmasq can still forward non-.consul queries once it takes over
# /etc/resolv.conf (needed for apt/Docker registry DNS lookups).
dnsmasq_upstream_dns_servers=["8.8.8.8", "1.1.1.1"]
