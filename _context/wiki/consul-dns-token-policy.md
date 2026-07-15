To enable Consul DNS queries when ACLs are enabled, you must create a policy with read permissions for nodes, services, and queries, then link it to a dedicated ACL token. 

1. Create the DNS Policy
Define an HCL file (e.g., dns-policy.hcl) with the following rules to allow the agent to discover resources:

node_prefix "" {
  policy = "read"
}

service_prefix "" {
  policy = "read"
}

query_prefix "" {
  policy = "read"
}

Register this policy using the management token:

consul acl policy create \
  -name "dns-access" \
  -rules @dns-policy.hcl \
  -description "DNS Policy"

2. Create the DNS Token
Generate a new ACL token linked to the dns-access policy:

consul acl token create \
  -description "DNS token" \
  -policy-name "dns-access"

3. Configure the Consul Agent
Assign the new token to the agent so it can respond to DNS queries. You can either:

Set the DNS-specific token (recommended for security):
consul acl set-agent-token dns <dns-token-secret-id>

Or set the default token (if no specific DNS token is configured, the agent uses the default):
consul acl set-agent-token default <dns-token-secret-id>

Alternatively, configure the token directly in the agent's consul.hcl configuration file under acl.tokens.default or acl.tokens.dns. 