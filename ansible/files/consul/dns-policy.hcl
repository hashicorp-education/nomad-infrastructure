# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy for DNS resolution.
#
# When ACLs are enabled with default-deny, the Consul agent's DNS server
# cannot respond to queries without a token that grants read access to
# services, nodes, and prepared queries.  Assigning this policy to a
# dedicated token and setting that token as the agent's DNS token (via
# `consul acl set-agent-token dns`) allows .global DNS lookups to work
# without granting the anonymous token any permissions.
#
# Required permissions:
#   service:read  — resolve service DNS lookups (A, AAAA, SRV records)
#   node:read     — resolve node DNS lookups
#   query:read    — resolve prepared query lookups
#
# References:
#   https://developer.hashicorp.com/consul/docs/secure/acl/token/dns

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

query_prefix "" {
  policy = "read"
}
