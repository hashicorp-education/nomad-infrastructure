# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
variable "project_name" {
  description = "Project name used for VM naming"
  type        = string
  default     = "nomad-consul-local"
}

variable "server_count" {
  description = "Number of Nomad/Consul server VMs"
  type        = number
  default     = 3
}

variable "client_count" {
  description = "Number of Nomad client VMs"
  type        = number
  default     = 2
}

variable "vm_cpus" {
  description = "Number of CPUs per VM"
  type        = number
  default     = 2
}

variable "vm_memory" {
  description = "Memory per VM (Multipass size string with KiB/MiB/GiB/TiB suffix)"
  type        = string
  default     = "4GiB"
}

variable "vm_disk" {
  description = "Disk space per VM (Multipass size string with KiB/MiB/GiB/TiB suffix)"
  type        = string
  default     = "10GiB"
}

variable "vm_image" {
  description = "Ubuntu release Multipass should launch (matches the AWS AMI's Ubuntu 24.04 noble)"
  type        = string
  default     = "24.04"
}

variable "ssh_user" {
  description = "SSH/Ansible user - matches the default user on Multipass's Ubuntu cloud images"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key injected into each VM via cloud-init. Supports ~ expansion."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_private_key_path" {
  description = "Path to the local SSH private key Ansible should use to connect. Not read by Terraform - written as-is into the generated inventory's ansible_ssh_private_key_file. Supports ~ expansion."
  type        = string
  default     = "~/.ssh/id_ed25519"
}
