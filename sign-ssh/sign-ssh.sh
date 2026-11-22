#!/bin/bash
set -euo pipefail

# shellcheck source=oidc-login.sh
source "$(dirname "${BASH_SOURCE[0]}")/../oidc-login.sh"

cleanup_keypair() {
  rm -f "$KEY_FILE" "$KEY_FILE.pub" "$KEY_FILE-cert.pub"
}

ssh-keygen -t ed25519 -N "" -f "$KEY_FILE" -q

CLIENT_TOKEN=$(oidc_login)
if [ -z "$CLIENT_TOKEN" ] || [ "$CLIENT_TOKEN" = "null" ]; then
  cleanup_keypair
  echo "Vault login for role $ROLE failed to return a client token" >&2
  exit 1
fi

SIGN_PAYLOAD=$(jq -n --rawfile pubkey "$KEY_FILE.pub" '{public_key: $pubkey}')
SIGNED_KEY=$(curl -sf -H "X-Vault-Token: $CLIENT_TOKEN" -X POST \
  "$VAULT_ADDR/v1/ssh/sign/$ROLE" -d "$SIGN_PAYLOAD" \
  | jq -r '.data.signed_key')
if [ -z "$SIGNED_KEY" ] || [ "$SIGNED_KEY" = "null" ]; then
  cleanup_keypair
  echo "OpenBao refused to sign the SSH key for role $ROLE" >&2
  exit 1
fi

echo "$SIGNED_KEY" > "$KEY_FILE-cert.pub"
chmod 600 "$KEY_FILE"
