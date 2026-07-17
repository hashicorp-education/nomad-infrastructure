Kind     = "http-route"
Name     = "countdash"

Parents = [
  {
    Kind        = "api-gateway"
    Name        = "api-gateway"
    SectionName = "https"
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
        Name   = "countdash-web"
        Weight = 100
      }
    ]
  }
]
