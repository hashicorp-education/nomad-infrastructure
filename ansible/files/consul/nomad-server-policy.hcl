# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy for Nomad server agents.
#
# Nomad servers need write access to register and manage services in the
# Consul catalog, manage ACL tokens for workload identities, and configure
# the Consul service mesh.
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

acl  = "write"
mesh = "write"
