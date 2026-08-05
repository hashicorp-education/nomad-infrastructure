# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Owner       = var.owner
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

output "ssh_instructions" {
  description = "SSH commands to access instances"
  value = <<-EOT
    ==========================================
    SSH Access Instructions
    ==========================================
    
    SSH Private Key Location: ../../ansible/ssh_key.pem
    
    Servers:
    %{for idx, instance in aws_instance.servers~}
      ssh -o 'IdentitiesOnly=yes' -i ../../ansible/ssh_key.pem ubuntu@${instance.public_ip}  # ${instance.tags.Name}
    %{endfor~}
    
    Clients:
    %{for idx, instance in aws_instance.clients~}
      ssh -o 'IdentitiesOnly=yes' -i ../../ansible/ssh_key.pem ubuntu@${instance.public_ip}  # ${instance.tags.Name}
    %{endfor~}
    
    Note: Ensure ssh_key.pem has correct permissions:
      chmod 600 ../../ansible/ssh_key.pem
    
    ==========================================
  EOT
}