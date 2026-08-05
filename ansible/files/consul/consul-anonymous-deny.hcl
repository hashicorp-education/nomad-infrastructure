# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Consul ACL policy: deny all access.
#
# Applied to the anonymous token (00000000-0000-0000-0000-000000000002) to
# make the default-deny behavior explicit for unauthenticated requests. This
# prevents accidental permission grants from future policy merges.
#
# Reference:
# https://developer.hashicorp.com/consul/docs/secure/acl/acl-rules
# policy name = anonymous-deny

acl = "deny"

agent_prefix "" {
  policy = "deny"
}

event_prefix "" {
  policy = "deny"
}

key_prefix "" {
  policy = "deny"
}

node_prefix "" {
  policy = "deny"
}

operator = "deny"

query_prefix "" {
  policy = "deny"
}

service_prefix "" {
  policy = "deny"
}

session_prefix "" {
  policy = "deny"
}
