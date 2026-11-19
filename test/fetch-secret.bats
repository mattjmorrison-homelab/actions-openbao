#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export VAULT_ADDR="http://vault.invalid"
  export ROLE="graph-hdmi-switch-discord"
  export KV_PATH="homelab/graph-hdmi-switch/discord-webhook-url"
  export OUTPUT_NAME="DISCORD_WEBHOOK_URL"
  export JWT_FILE="$BATS_TEST_TMPDIR/jwt"
  echo "fake-jwt" > "$JWT_FILE"
  export GITHUB_ENV="$BATS_TEST_TMPDIR/github_env"
  : > "$GITHUB_ENV"
}

github_env_value() {
  local name="$1" delim
  delim=$(awk -F '<<' -v n="$name" '$1==n{print $2}' "$GITHUB_ENV")
  [ -n "$delim" ] || return 1
  awk -v n="$name" -v d="$delim" '
    $0 == n "<<" d { grab=1; next }
    grab && $0 == d { grab=0; next }
    grab { print }
  ' "$GITHUB_ENV"
}

@test "exports the fetched value under OUTPUT_NAME" {
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(github_env_value "$OUTPUT_NAME")" = "https://discord.example/webhook" ]
}

@test "exports a multi-line fetched value correctly via the GITHUB_ENV heredoc form" {
  MOCK_SECRET_VALUE=$'-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\nBBBB\n-----END OPENSSH PRIVATE KEY-----'
  export MOCK_SECRET_VALUE
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(github_env_value "$OUTPUT_NAME")" = "$MOCK_SECRET_VALUE" ]
}

@test "masks the fetched value in output" {
  export MOCK_SECRET_VALUE="topsecret"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [[ "$output" == *"::add-mask::topsecret"* ]]
}

@test "fails when the Vault login doesn't return a client token" {
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to return a client token"* ]]
  [ ! -s "$GITHUB_ENV" ]
}

@test "fails when the KV fetch returns no value" {
  export MOCK_FETCH_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to fetch"* ]]
  [ ! -s "$GITHUB_ENV" ]
}

@test "fetches via OIDC login when AUTH_METHOD=oidc" {
  export AUTH_METHOD="oidc"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(github_env_value "$OUTPUT_NAME")" = "https://discord.example/webhook" ]
}

@test "fails when the OIDC Vault login doesn't return a client token" {
  export AUTH_METHOD="oidc"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to return a client token"* ]]
  [ ! -s "$GITHUB_ENV" ]
}
