#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export VAULT_ADDR="http://vault.invalid"
  export ROLE="ui-hdmi-switch-discord"
  export KV_PATH="homelab/ui-hdmi-switch/discord-webhook-url"
  export VALUE="https://discord.example/webhook"
  export JWT_FILE="$BATS_TEST_TMPDIR/jwt"
  echo "fake-jwt" > "$JWT_FILE"
  export CURL_CALL_LOG="$BATS_TEST_TMPDIR/curl-calls.log"
}

@test "writes the given value to the given kv-path" {
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -eq 0 ]
  grep -qF "$VAULT_ADDR/v1/kv/data/$KV_PATH" "$CURL_CALL_LOG"
  grep -qF '"value": "https://discord.example/webhook"' "$CURL_CALL_LOG"
}

@test "masks the value before doing anything else, even if login later fails" {
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::add-mask::https://discord.example/webhook"* ]]
}

@test "masks a multi-line value one physical line at a time" {
  VALUE=$'-----BEGIN KEY-----\nAAAA\nBBBB\n-----END KEY-----'
  export VALUE
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [[ "$output" == *"::add-mask::-----BEGIN KEY-----"* ]]
  [[ "$output" == *"::add-mask::AAAA"* ]]
  [[ "$output" == *"::add-mask::BBBB"* ]]
  [[ "$output" == *"::add-mask::-----END KEY-----"* ]]
  while IFS= read -r line; do
    [[ "$output" == *"::add-mask::${line}"* ]]
  done <<< "$VALUE"
}

@test "fails when the Vault login doesn't return a client token" {
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to return a client token"* ]]
}

@test "fails when the KV write returns no version" {
  export MOCK_WRITE_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to write"* ]]
}

@test "writes the given value via OIDC login when AUTH_METHOD=oidc" {
  export AUTH_METHOD="oidc"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -eq 0 ]
  grep -qF "$VAULT_ADDR/v1/kv/data/$KV_PATH" "$CURL_CALL_LOG"
  grep -qF '"value": "https://discord.example/webhook"' "$CURL_CALL_LOG"
}

@test "fails when the OIDC Vault login doesn't return a client token" {
  export AUTH_METHOD="oidc"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../write-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to return a client token"* ]]
}
