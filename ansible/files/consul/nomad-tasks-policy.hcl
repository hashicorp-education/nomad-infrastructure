# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy for Nomad task workload identities.
#
# Tasks running in Nomad can use their workload identity JWT to obtain a
# Consul ACL token. This policy grants read access to services, nodes, and
# key/value paths — sufficient for service discovery and template rendering
# via Nomad's template block.
#
# Restrict paths further in production to meet least-privilege requirements.
#
# Reference: https://developer.hashicorp.com/nomad/tutorials/integrate-consul/consul-acl

key_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
