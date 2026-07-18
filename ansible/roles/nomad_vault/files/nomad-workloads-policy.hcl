# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# nomad-workloads-policy.hcl
#
# Vault ACL policy for Nomad task workload identities.
#
# Assigned to the nomad-workloads JWT role. Grants read-only access to a
# KV v2 mount so Nomad tasks can retrieve secrets with a `vault {}` block and
# `template` stanza, without a static Vault token.

path "secret/data/nomad/*" {
  capabilities = ["read"]
}

path "secret/metadata/nomad/*" {
  capabilities = ["list", "read"]
}
