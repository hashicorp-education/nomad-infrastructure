# Consul inline-certificate config entry for the API Gateway TLS listener.
#
# This file is a TEMPLATE — do NOT write your cert/key inline and commit.
# Generate the certificate and write the config entry in a single pipeline:
#
#   Step 1: generate a self-signed certificate for the gateway listener
#
#     openssl req -x509 -nodes -newkey rsa:2048 \
#       -keyout /tmp/gateway.key \
#       -out /tmp/gateway.crt \
#       -days 365 \
#       -subj "/CN=api-gateway.local" \
#       -addext "subjectAltName=IP:<your_node_public_ip>"
#
#   Step 2: apply the config entry with the cert/key inlined
#
#     consul config write - <<EOF
#     Kind        = "inline-certificate"
#     Name        = "api-gateway-cert"
#     Certificate = "$(cat /tmp/gateway.crt)"
#     PrivateKey  = "$(cat /tmp/gateway.key)"
#     EOF
#
# The Name "api-gateway-cert" must match the CertificateRef in gateway-listener.hcl.
#
# For production use, replace this with a file-system-certificate config entry
# that references cert/key files deployed to the nodes via the tls role.
#
# After applying, verify with:
#   consul config read -kind inline-certificate -name api-gateway-cert
