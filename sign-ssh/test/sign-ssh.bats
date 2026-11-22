#!/usr/bin/env bats

setup() {
  export PATH="$BATS_TEST_DIRNAME/mocks:$PATH"
  export VAULT_ADDR="http://vault.invalid"
  export ROLE="pi-fleet"
  export KEY_FILE="$BATS_TEST_TMPDIR/id_ed25519"
  export ACTIONS_ID_TOKEN_REQUEST_TOKEN="fake-request-token"
  export ACTIONS_ID_TOKEN_REQUEST_URL="http://token.invalid/api/v3"
  export CURL_CALL_LOG="$BATS_TEST_TMPDIR/curl-calls.log"
}

@test "generates a keypair and writes the signed cert alongside it" {
  export MOCK_SIGNED_KEY="ssh-ed25519-cert-v01@openssh.com AAAAfakecert pi-fleet"
  run bash "$BATS_TEST_DIRNAME/../sign-ssh.sh"
  [ "$status" -eq 0 ]
  [ -s "$KEY_FILE" ]
  [ -s "$KEY_FILE.pub" ]
  [ "$(cat "$KEY_FILE-cert.pub")" = "$MOCK_SIGNED_KEY" ]
  [ "$(stat -c '%a' "$KEY_FILE")" = "600" ]
  grep -qF "$VAULT_ADDR/v1/ssh/sign/$ROLE" "$CURL_CALL_LOG"
}

@test "fails loudly and cleans up the keypair when OpenBao returns no signed_key" {
  export MOCK_SIGN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../sign-ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refused to sign"* ]]
  [ ! -e "$KEY_FILE" ]
  [ ! -e "$KEY_FILE.pub" ]
  [ ! -e "$KEY_FILE-cert.pub" ]
}

@test "fails loudly and cleans up the keypair when the Vault login fails" {
  export MOCK_LOGIN_FAILS="true"
  run bash "$BATS_TEST_DIRNAME/../sign-ssh.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to return a client token"* ]]
  [ ! -e "$KEY_FILE" ]
  [ ! -e "$KEY_FILE.pub" ]
  [ ! -e "$KEY_FILE-cert.pub" ]
}

@test "never prints the private key to stdout or stderr" {
  export MOCK_SIGNED_KEY="ssh-ed25519-cert-v01@openssh.com AAAAfakecert pi-fleet"
  run bash "$BATS_TEST_DIRNAME/../sign-ssh.sh"
  [ "$status" -eq 0 ]
  key_contents="$(cat "$KEY_FILE")"
  [[ "$output" != *"$key_contents"* ]]
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    [[ "$output" != *"$line"* ]]
  done < "$KEY_FILE"
}
