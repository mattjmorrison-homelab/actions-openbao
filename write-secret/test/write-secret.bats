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
