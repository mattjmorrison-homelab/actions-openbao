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
  export OUTPUT_FILE_PATH="$BATS_TEST_TMPDIR/secret-out"
}

github_env_value() {
  local name="$1"
  awk -F '=' -v n="$name" '$1==n{sub(n"=", ""); print}' "$GITHUB_ENV"
}

@test "exports the fetched value under OUTPUT_NAME" {
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(github_env_value "$OUTPUT_NAME")" = "https://discord.example/webhook" ]
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

@test "fails loudly when a fetched multi-line value is sent to output-name" {
  export MOCK_SECRET_VALUE=$'-----BEGIN KEY-----\nAAAA\n-----END KEY-----'
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"output-file"* ]]
  [ ! -s "$GITHUB_ENV" ]
}

@test "fails when both output-name and output-file are set" {
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Exactly one of output-name/output-file"* ]]
}

@test "fails when neither output-name nor output-file is set" {
  unset OUTPUT_NAME
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Exactly one of output-name/output-file"* ]]
}

@test "output-file: writes a single-line fetched value directly to the file" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_FILE")" = "https://discord.example/webhook" ]
}

@test "output-file: writes a multi-line PEM value directly to the file" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  MOCK_SECRET_VALUE=$'-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\nBBBB\n-----END OPENSSH PRIVATE KEY-----'
  export MOCK_SECRET_VALUE
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_FILE")" = "$MOCK_SECRET_VALUE" ]
}

@test "output-file: writes with 0600 permissions" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  export MOCK_SECRET_VALUE="https://discord.example/webhook"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(stat -c '%a' "$OUTPUT_FILE")" = "600" ]
}

@test "output-file: removes the file when the KV fetch fails" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  export MOCK_FETCH_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Failed to fetch"* ]]
  [ ! -e "$OUTPUT_FILE" ]
}

@test "output-file: removes the file when the Vault login fails" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -ne 0 ]
  [ ! -e "$OUTPUT_FILE" ]
}

@test "output-file: a multi-line secret never appears in the script's output (kubernetes auth)" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  MOCK_SECRET_VALUE=$'-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAsupersecretline1\nBBBBsupersecretline2\n-----END OPENSSH PRIVATE KEY-----'
  export MOCK_SECRET_VALUE
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_FILE")" = "$MOCK_SECRET_VALUE" ]
  while IFS= read -r line; do
    [[ "$output" != *"$line"* ]]
  done <<< "$MOCK_SECRET_VALUE"
}

@test "output-file: a multi-line secret never appears in the script's output (oidc auth)" {
  unset OUTPUT_NAME
  export OUTPUT_FILE="$OUTPUT_FILE_PATH"
  export AUTH_METHOD="oidc"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  MOCK_SECRET_VALUE=$'-----BEGIN OPENSSH PRIVATE KEY-----\nAAAAsupersecretline1\nBBBBsupersecretline2\n-----END OPENSSH PRIVATE KEY-----'
  export MOCK_SECRET_VALUE
  run bash "$BATS_TEST_DIRNAME/../fetch-secret.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$OUTPUT_FILE")" = "$MOCK_SECRET_VALUE" ]
  while IFS= read -r line; do
    [[ "$output" != *"$line"* ]]
  done <<< "$MOCK_SECRET_VALUE"
}
