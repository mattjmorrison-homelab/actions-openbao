#!/bin/bash
set -euo pipefail

AUTH_METHOD="${AUTH_METHOD:-kubernetes}"
OUTPUT_NAME="${OUTPUT_NAME:-}"
OUTPUT_FILE="${OUTPUT_FILE:-}"

if [ -n "$OUTPUT_NAME" ] && [ -n "$OUTPUT_FILE" ]; then
  echo "Exactly one of output-name/output-file must be set, not both" >&2
  exit 1
fi
if [ -z "$OUTPUT_NAME" ] && [ -z "$OUTPUT_FILE" ]; then
  echo "Exactly one of output-name/output-file must be set" >&2
  exit 1
fi

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

if [ -n "$OUTPUT_FILE" ]; then
  if ! curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" "$VAULT_ADDR/v1/kv/data/$KV_PATH" \
      | jq -r '.data.data.value' > "$OUTPUT_FILE"; then
    rm -f "$OUTPUT_FILE"
    echo "Failed to fetch $KV_PATH from OpenBao" >&2
    exit 1
  fi
  if [ ! -s "$OUTPUT_FILE" ] || [ "$(<"$OUTPUT_FILE")" = "null" ]; then
    rm -f "$OUTPUT_FILE"
    echo "Failed to fetch $KV_PATH from OpenBao" >&2
    exit 1
  fi
  chmod 600 "$OUTPUT_FILE"
else
  VALUE=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" "$VAULT_ADDR/v1/kv/data/$KV_PATH" \
    | jq -r '.data.data.value')
  if [ -z "$VALUE" ] || [ "$VALUE" = "null" ]; then
    echo "Failed to fetch $KV_PATH from OpenBao" >&2
    exit 1
  fi
  if [[ "$VALUE" == *$'\n'* ]]; then
    echo "Fetched value for $KV_PATH spans multiple lines; use output-file instead of output-name" >&2
    exit 1
  fi

  echo "::add-mask::$VALUE"
  echo "${OUTPUT_NAME}=${VALUE}" >> "$GITHUB_ENV"
fi
