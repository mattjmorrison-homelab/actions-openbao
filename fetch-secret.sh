#!/bin/bash
set -euo pipefail

AUTH_METHOD="${AUTH_METHOD:-kubernetes}"

if [ "$AUTH_METHOD" = "oidc" ]; then
  # shellcheck source=oidc-login.sh
  source "$(dirname "${BASH_SOURCE[0]}")/oidc-login.sh"
  CLIENT_TOKEN=$(oidc_login)
else
  JWT_FILE="${JWT_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}"
  LOGIN_PAYLOAD=$(jq -n \
    --arg jwt "$(cat "$JWT_FILE")" \
    --arg role "$ROLE" \
    '{jwt: $jwt, role: $role}')
  CLIENT_TOKEN=$(curl -sf -X POST "$VAULT_ADDR/v1/auth/kubernetes/login" -d "$LOGIN_PAYLOAD" \
    | jq -r '.auth.client_token')
fi
if [ -z "$CLIENT_TOKEN" ] || [ "$CLIENT_TOKEN" = "null" ]; then
  echo "Vault login for role $ROLE failed to return a client token" >&2
  exit 1
fi

VALUE=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" "$VAULT_ADDR/v1/kv/data/$KV_PATH" \
  | jq -r '.data.data.value')
if [ -z "$VALUE" ] || [ "$VALUE" = "null" ]; then
  echo "Failed to fetch $KV_PATH from OpenBao" >&2
  exit 1
fi

echo "::add-mask::$VALUE"

# Random per run so it can't collide with a line inside VALUE.
DELIMITER="ghadelim_$(date +%s%N)_${RANDOM}${RANDOM}_$$"
{
  echo "${OUTPUT_NAME}<<${DELIMITER}"
  echo "${VALUE}"
  echo "${DELIMITER}"
} >> "$GITHUB_ENV"
