# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# VPC Configuration
resource "aws_vpc" "nomad_consul_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name  = "${var.project_name}-vpc"
    Owner = var.owner
  }
}

# Internet Gateway
resource "aws_internet_gateway" "nomad_consul_igw" {
  vpc_id = aws_vpc.nomad_consul_vpc.id

  tags = {
    Name  = "${var.project_name}-igw"
    Owner = var.owner
  }
}

resource "aws_default_route_table" "nomad_consul_route_table" {
  default_route_table_id = aws_vpc.nomad_consul_vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nomad_consul_igw.id
  }

 tags = {
    Name  = "${var.project_name}-public-rt"
    Owner = var.owner
  }
}
resource "aws_subnet" "subnet" {
  vpc_id                  = aws_vpc.nomad_consul_vpc.id
  cidr_block              = var.subnet_cidr
  map_public_ip_on_launch = true # Need this. If false, output does not print public IP
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = {
    Name  = "${var.project_name}-public-subnet"
    Owner = var.owner
  }
}


# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}


#-------------------------------------------------------------------------------
# Security Group
#-------------------------------------------------------------------------------

resource "aws_security_group" "nomad_consul_sg" {
  name        = "${var.project_name}-sg"
  description = "Security group for Nomad and Consul cluster managed by Terraform and Ansible"
  vpc_id      = aws_vpc.nomad_consul_vpc.id

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
    description = "SSH access"
  }

# Consul HTTP API and UI
  ingress {
    from_port   = 8500
    to_port     = 8500
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Consul UI and HTTP API"
  }


# Nomad HTTP API and UI
  ingress {
    from_port   = 4646
    to_port     = 4646
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Nomad UI and HTTP API"
  }

# Countdash example app web UI
  ingress {
    from_port   = 9002
    to_port     = 9002
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Countdash example app - web UI"
  }

  # Allow all internal traffic
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
    description = "Allow all internal traffic"
  }

  # Egress - allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  

  tags = {
    Name  = "${var.project_name}-sg"
    Owner = var.owner
  }
}
