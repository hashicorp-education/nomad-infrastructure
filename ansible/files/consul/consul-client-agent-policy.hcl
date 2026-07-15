# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy for Consul client agent operations.
#
# When ACLs are enabled on Consul client agents, this policy allows the
# agent to register its own node in the Consul catalog and read catalog
# data needed for service discovery and health checks.
#
# Applied as acl.tokens.agent in /etc/consul.d/dns-acl.hcl on client nodes.
# The separate dns-access policy is used for acl.tokens.dns.
#
# Reference:
#   https://developer.hashicorp.com/consul/docs/secure/acl/token/agent

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}
