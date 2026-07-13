# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# nomad-server-policy.hcl
#
# Consul ACL policy for Nomad server agents (service discovery integration).
#
# Nomad servers must be able to:
#   - Read agent and node information to discover the cluster topology
#   - Register themselves as Consul services
#   - Write ACLs so they can create and manage tokens for Nomad client agents

agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "write"
}

acl = "write"
