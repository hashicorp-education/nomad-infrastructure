# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
[servers]
%{ for name, instance in servers ~}
${name} ansible_host=${instance.ip} private_ip=${instance.private_ip}
%{ endfor ~}

[clients]
%{ for name, instance in clients ~}
${name} ansible_host=${instance.ip} private_ip=${instance.private_ip} nomad_node_role=${instance.role}
%{ endfor ~}

[all:vars]
ansible_user=${ssh_user}
ansible_ssh_private_key_file=ssh_key.pem
ansible_python_interpreter=/usr/bin/python3