# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy for Nomad client agents.
#
# Nomad clients need write access to register and deregister services and
# health checks in the Consul catalog on behalf of running workloads.
#
# Reference: https://developer.hashicorp.com/nomad/docs/secure/acl/consul#nomad-agents

agent_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "write"
}
