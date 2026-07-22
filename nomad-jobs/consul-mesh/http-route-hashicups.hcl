Kind     = "http-route"
Name     = "hashicups"

Parents = [
  {
    Kind        = "api-gateway"
    Name        = "api-gateway"
    SectionName = "https-hashicups"
  }
]

Rules = [
  {
    Matches = [
      {
        Path = {
          Match = "prefix"
          Value = "/"
        }
      }
    ]

    Services = [
      {
        Name   = "nginx"
        Weight = 100
      }
    ]
  }
]
