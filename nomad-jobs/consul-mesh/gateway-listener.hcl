Kind = "api-gateway"
Name = "api-gateway"

Listeners = [
  {
    Name     = "https"
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
  }
]
