Kind = "service-intentions"
Name = "nginx"

Sources = [
  {
    Name   = "api-gateway"
    Action = "allow"
  }
]
