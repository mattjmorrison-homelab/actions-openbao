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

@test "exports the fetched value under OUTPUT_NAME" {
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  grep -qF "DISCORD_WEBHOOK_URL=https://discord.example/webhook" "$GITHUB_ENV"
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
