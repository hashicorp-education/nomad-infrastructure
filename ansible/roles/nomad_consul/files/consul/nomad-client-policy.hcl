# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# nomad-client-policy.hcl
#
# Consul ACL policy for Nomad client agents (service discovery integration).
#
# Nomad clients must be able to:
#   - Read agent and node information to discover the cluster topology
#   - Register and deregister workloads as Consul services
#   - Perform health checks on registered services

agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "write"
}
