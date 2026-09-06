#!/bin/bash
set -euo pipefail

echo "::add-mask::$VALUE"

JWT_FILE="${JWT_FILE:-/var/run/secrets/kubernetes.io/serviceaccount/token}"

LOGIN_PAYLOAD=$(jq -n \
  --arg jwt "$(cat "$JWT_FILE")" \
  --arg role "$ROLE" \
  '{jwt: $jwt, role: $role}')
CLIENT_TOKEN=$(curl -sf -X POST "$VAULT_ADDR/v1/auth/kubernetes/login" -d "$LOGIN_PAYLOAD" \
  | jq -r '.auth.client_token')
if [ -z "$CLIENT_TOKEN" ] || [ "$CLIENT_TOKEN" = "null" ]; then
  echo "Vault login for role $ROLE failed to return a client token" >&2
  exit 1
fi

WRITE_PAYLOAD=$(jq -n --arg v "$VALUE" '{data: {value: $v}}')
VERSION=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" -X POST \
  "$VAULT_ADDR/v1/kv/data/$KV_PATH" -d "$WRITE_PAYLOAD" \
  | jq -r '.data.version')
if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
  echo "Failed to write $KV_PATH to OpenBao" >&2
  exit 1
fi
