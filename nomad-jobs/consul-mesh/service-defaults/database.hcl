Kind = "service-defaults"
Name = "database"

# PostgreSQL speaks TCP — must not be "http". Consul uses this to determine
# how the sidecar proxy handles the connection (layer 4 only, no L7 inspection).
Protocol = "tcp"
