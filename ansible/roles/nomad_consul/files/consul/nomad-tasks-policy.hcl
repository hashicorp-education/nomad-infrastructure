# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# nomad-tasks-policy.hcl
#
# Consul ACL policy for Nomad task workload identities.
#
# Assigned to the nomad-tasks-default ACL role, which task workload identity
# JWTs (from Nomad's task identity) map to via a Consul ACL binding rule.
# Tasks using `template` blocks need to read KV and resolve service addresses.

key_prefix "" {
  policy = "read"
}

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}
