#cloud-config
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# Appends the user's existing SSH public key to the default 'ubuntu' user
# that Multipass's Ubuntu cloud images already create. This is additive -
# it does not define a users: block, so it does not disable password auth
# or otherwise redefine the default user.
ssh_authorized_keys:
  - ${ssh_public_key}
