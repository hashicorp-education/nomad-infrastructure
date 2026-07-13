#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# ============================================================
# unset-cluster-env.sh
#
# Unsets Consul and Nomad environment variables.
#
# Usage:
#   source ./unset-cluster-env.sh
# ============================================================

# This script must be sourced, not executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed." >&2
    echo "Usage: source ${0}" >&2
    exit 1
fi

unset CONSUL_HTTP_ADDR
unset CONSUL_HTTP_TOKEN
unset NOMAD_ADDR
unset NOMAD_TOKEN

echo "Unset cluster environment variables:"
echo "  CONSUL_HTTP_ADDR, CONSUL_HTTP_TOKEN, NOMAD_ADDR, NOMAD_TOKEN"
