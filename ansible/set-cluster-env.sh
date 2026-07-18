#!/usr/bin/env bash
# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0
# ============================================================
# set-cluster-env.sh
#
# Sets Consul and Nomad environment variables for cluster access.
# Reads bootstrap tokens from the ansible/ directory and determines
# the server address from inventory.ini.
#
# Usage:
#   source ./set-cluster-env.sh
#
# To unset the variables:
#   source ./unset-cluster-env.sh
# ============================================================

# This script must be sourced, not executed directly.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "ERROR: This script must be sourced, not executed." >&2
    echo "Usage: source ${0}" >&2
    exit 1
fi

_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_INVENTORY="${_SCRIPT_DIR}/inventory.ini"

# Require inventory.ini
if [[ ! -f "${_INVENTORY}" ]]; then
    echo "ERROR: inventory.ini not found at ${_INVENTORY}" >&2
    echo "       Run terraform apply in terraform/aws/ to generate it." >&2
    unset _SCRIPT_DIR _INVENTORY
    return 1
fi

# Read the first server's public IP from the [servers] group in inventory.ini
_SERVER_IP=$(awk '/^\[servers\]/{found=1; next} found && /^[^[#[:space:]]/{print; exit}' \
    "${_INVENTORY}" | awk -F'ansible_host=' '{print $2}' | awk '{print $1}')

if [[ -z "${_SERVER_IP}" ]]; then
    echo "ERROR: Could not read a server IP from ${_INVENTORY}" >&2
    echo "       Ensure [servers] group exists and has at least one host." >&2
    unset _SCRIPT_DIR _INVENTORY _SERVER_IP
    return 1
fi

echo "Setting cluster environment variables (server: ${_SERVER_IP}):"
echo ""

# ── Consul ────────────────────────────────────────────────────────────────────
_CONSUL_TOKEN_FILE="${_SCRIPT_DIR}/tokens/consul-bootstrap-secret-id.txt"
_TLS_CA_FILE="${_SCRIPT_DIR}/.tls/ca.pem"
if [[ -f "${_CONSUL_TOKEN_FILE}" ]]; then
    export CONSUL_HTTP_ADDR="https://${_SERVER_IP}:8443"
    export CONSUL_HTTP_TOKEN="$(cat "${_CONSUL_TOKEN_FILE}")"
    echo "  CONSUL_HTTP_ADDR=${CONSUL_HTTP_ADDR}"
    echo "  CONSUL_HTTP_TOKEN=(set from consul-bootstrap-secret-id.txt)"
    if [[ -f "${_TLS_CA_FILE}" ]]; then
        export CONSUL_CACERT="${_TLS_CA_FILE}"
        echo "  CONSUL_CACERT=${CONSUL_CACERT}"
    fi
else
    echo "  CONSUL_HTTP_ADDR / CONSUL_HTTP_TOKEN: skipped"
    echo "    (consul-bootstrap-secret-id.txt not found — run consul_acl_bootstrap.yaml)"
fi

# ── Nomad ─────────────────────────────────────────────────────────────────────
_NOMAD_TOKEN_FILE="${_SCRIPT_DIR}/tokens/nomad-bootstrap-secret-id.txt"
if [[ -f "${_NOMAD_TOKEN_FILE}" ]]; then
    export NOMAD_ADDR="https://${_SERVER_IP}:4646"
    export NOMAD_TOKEN="$(cat "${_NOMAD_TOKEN_FILE}")"
    echo "  NOMAD_ADDR=${NOMAD_ADDR}"
    echo "  NOMAD_TOKEN=(set from nomad-bootstrap-secret-id.txt)"
    if [[ -f "${_TLS_CA_FILE}" ]]; then
        export NOMAD_CACERT="${_TLS_CA_FILE}"
        echo "  NOMAD_CACERT=${NOMAD_CACERT}"
    fi
else
    echo "  NOMAD_ADDR / NOMAD_TOKEN: skipped"
    echo "    (nomad-bootstrap-secret-id.txt not found — run nomad_acl_bootstrap.yaml)"
fi

# ── Vault ─────────────────────────────────────────────────────────────────────
_VAULT_TOKEN_FILE="${_SCRIPT_DIR}/tokens/vault-root-token-secret-id.txt"
if [[ -f "${_VAULT_TOKEN_FILE}" ]]; then
    export VAULT_ADDR="https://${_SERVER_IP}:8200"
    export VAULT_TOKEN="$(cat "${_VAULT_TOKEN_FILE}")"
    echo "  VAULT_ADDR=${VAULT_ADDR}"
    echo "  VAULT_TOKEN=(set from vault-root-token-secret-id.txt)"
    if [[ -f "${_TLS_CA_FILE}" ]]; then
        export VAULT_CACERT="${_TLS_CA_FILE}"
        echo "  VAULT_CACERT=${VAULT_CACERT}"
    fi
else
    echo "  VAULT_ADDR / VAULT_TOKEN: skipped"
    echo "    (vault-root-token-secret-id.txt not found — run vault_servers.yaml)"
fi

echo ""

unset _SCRIPT_DIR _INVENTORY _SERVER_IP _CONSUL_TOKEN_FILE _NOMAD_TOKEN_FILE _VAULT_TOKEN_FILE _TLS_CA_FILE
