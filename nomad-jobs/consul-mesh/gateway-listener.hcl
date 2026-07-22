Kind = "api-gateway"
Name = "api-gateway"

# Two listeners, one per demo app, so Countdash and HashiCups are reachable
# simultaneously instead of sharing one path-based route where only the
# most-recently-applied http-route wins (see http-route-countdash.hcl /
# http-route-hashicups.hcl, and _context/wiki/dedicated-ingress-node-plan.md).
# Both reuse the same inline-certificate — the cert's SAN is the ingress
# node's IP, which doesn't vary by port.
Listeners = [
  {
    Name     = "https-countdash"
    Port     = 8447
    Protocol = "http"

    TLS = {
      MinVersion = "TLSv1_2"

      Certificates = [
        {
          Kind = "inline-certificate"
          Name = "api-gateway-cert"
        }
      ]
    }
  },
  {
    Name     = "https-hashicups"
    Port     = 8448
    Protocol = "http"

    TLS = {
      MinVersion = "TLSv1_2"

      Certificates = [
        {
          Kind = "inline-certificate"
          Name = "api-gateway-cert"
        }
      ]
    }
  }
]
