# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Data source for Ubuntu AMI
data "aws_ami" "chosen_ami" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }

  filter {
    name = "architecture"
    values = [var.ami_architecture]
  }
}
