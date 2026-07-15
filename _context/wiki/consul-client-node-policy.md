To create tokens and policies for each client node in HashiCorp Consul, you should define an ACL policy that grants node:write and service:read permissions, register that policy, and then create a token linked to it. 

1. Define the Node Policy Create an HCL file (e.g., node-policy.hcl) that allows the agent to register itself and discover other services. You can use a wildcard to apply this to all nodes or specify individual node names. 

node_prefix "" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}

2. Create the Policy Use the Consul CLI to register the policy file. You must use a token with acl:write permissions (such as the bootstrap token) to create policies. 

consul acl policy create \
  -name "node-policy" \
  -rules @node-policy.hcl \
  -token=${CONSUL_MGMT_TOKEN}

3. Create the Node Token Generate a token linked to the newly created policy. This token will be used by the specific client node. 

consul acl token create \
  -description "Node token for node1" \
  -policy-name "node-policy" \
  -token=${CONSUL_MGMT_TOKEN}

4. Configure the Agent On each client node, set the generated token in the Consul agent configuration file (acl.hcl) or via the CONSUL_HTTP_TOKEN environment variable so the agent can present it during registration. 

acl {
  enabled = true
  tokens {
    agent = "<paste-the-new-token-secret-id-here>"
  }
}

Alternative: Node Identities For easier management, Consul recommends using node identities instead of custom policies for agent registration.  You can create a token linked directly to a node identity:

consul acl token create \
  -description "Agent token for node1" \
  -node-identity "node1:dc1" \
  -token=${CONSUL_MGMT_TOKEN}

Node identities automatically grant node:write and service:read permissions, eliminating the need to manually define and maintain policy files for each node. 

