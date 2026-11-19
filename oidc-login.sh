#!/bin/bash
# Shared GitHub-OIDC-to-Vault login step for fetch-secret.sh and
# write-secret/write-secret.sh. ACTIONS_ID_TOKEN_REQUEST_TOKEN and
# ACTIONS_ID_TOKEN_REQUEST_URL are already present in any job step with
# `permissions: id-token: write` -- no workflow YAML passthrough needed.
# Mirrors admin-discord/scripts/lib/vault-oidc-login.sh, the reference
# implementation already proven elsewhere in this homelab.

oidc_login() {
  local gh_oidc_token
  gh_oidc_token=$(curl -sf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
    "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=openbao" | jq -r '.value')

  curl -sf -X POST "$VAULT_ADDR/v1/auth/jwt/login" \
    -d "$(jq -nc --arg jwt "$gh_oidc_token" --arg role "$ROLE" '{jwt: $jwt, role: $role}')" \
    | jq -r '.auth.client_token'
}
