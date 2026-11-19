# actions-openbao

Reusable GitHub Actions composite actions for talking to OpenBao from
CI: the root action logs into OpenBao via this pod's own Kubernetes
ServiceAccount identity, fetches one KV secret, masks it, and exports it
as an env var for the rest of the job. `write-secret/` is the write-side
counterpart -- same login, but writes a value instead of reading one.

Named for the tool it wraps (OpenBao), same reasoning as `admin-openbao`
over `admin-vault` and `actions-tofu` over `actions-terraform`.

## Why this exists

The curl+jq Kubernetes-auth-login-then-fetch pattern was already
duplicated twice before this repo existed: `pi-provision`'s
`fetch-openbao-secret.sh` (fetches one secret, prints it to stdout) and
`actions-tofu`'s `fetch-credentials.sh` (a more specialized, multi-secret
variant hardcoded to `admin-github`/`admin-openbao`'s own needs). Neither
of those two is being replaced here — they stay as they are. This repo
exists so a *third* caller needing the same login-then-fetch-one-secret
shape (starting with the Discord-webhook fetch for `graph-hdmi-switch`
and `ui-hdmi-switch`'s CI, migrating off Woodpecker) has somewhere generic
to reach for, instead of copying either existing script a second time.

## Inputs

| Input | Type | Default | Notes |
| --- | --- | --- | --- |
| `role` | string | *(required)* | OpenBao role to log in as (Kubernetes-auth or JWT/OIDC, per `auth-method`). |
| `auth-method` | string | `kubernetes` | `kubernetes` logs in via this pod's own ServiceAccount token. `oidc` logs in via a GitHub Actions OIDC token against `auth/jwt/login` instead -- use this from a GitHub-hosted (non-cluster) runner, or any job migrated off Kubernetes-auth. Requires the job to set `permissions: id-token: write`. |
| `kv-path` | string | *(required)* | KV path to read, relative to `kv/data/` (e.g. `homelab/graph-hdmi-switch/discord-webhook-url`). |
| `output-name` | string | *(required)* | Env var name to export the fetched value as. |
| `vault-addr` | string | `http://k8s-openbao.openbao.svc:8200` | OpenBao address. |

## Using it from another repo

```yaml
- uses: mattjmorrison-homelab/actions-openbao@<commit-sha>
  with:
    role: graph-hdmi-switch-discord
    kv-path: homelab/graph-hdmi-switch/discord-webhook-url
    output-name: DISCORD_WEBHOOK_URL
- if: failure()
  run: curl -sf -X POST "$DISCORD_WEBHOOK_URL" -d '{"content": "build failed"}'
```

From a job authenticating via GitHub OIDC instead of Kubernetes-auth:

```yaml
permissions:
  id-token: write
steps:
  - uses: mattjmorrison-homelab/actions-openbao@<commit-sha>
    with:
      role: graph-hdmi-switch-discord
      auth-method: oidc
      kv-path: homelab/graph-hdmi-switch/discord-webhook-url
      output-name: DISCORD_WEBHOOK_URL
```

**Pin to a commit SHA, not a branch** -- this org requires
`sha_pinning_required` on every `uses:` reference. Get the current SHA
with:

```sh
gh api repos/mattjmorrison-homelab/actions-openbao/commits/main --jq '.sha'
```

No automation keeps these pins current today; update every caller's pin
manually after any change here that should actually take effect.

## write-secret/

The write-side counterpart to the root `fetch-secret` action -- logs in
the same way, but writes one KV secret instead of reading one. Lives in
a subdirectory rather than at the repo root (unlike `fetch-secret`)
purely so adding it doesn't change the root action's `uses:` path for
every existing caller.

Built for a pull-based pattern: a repo that already owns a KV path (e.g.
`ui-hdmi-switch`'s `homelab/ui-hdmi-switch/discord-webhook-url`)
populates it itself, from a value it pulled from another repo's
Terraform state via `actions-tofu/read-output` -- rather than that other
repo needing write access to `ui-hdmi-switch`'s own secrets.

| Input | Type | Default | Notes |
| --- | --- | --- | --- |
| `role` | string | *(required)* | OpenBao role to log in as (Kubernetes-auth or JWT/OIDC, per `auth-method`). Needs `create`/`update` capability on `kv-path`, not just `read`. |
| `auth-method` | string | `kubernetes` | Same as the root `fetch-secret` action's `auth-method` -- `kubernetes` or `oidc`. `oidc` requires the job to set `permissions: id-token: write`. |
| `kv-path` | string | *(required)* | KV path to write, relative to `kv/data/`. |
| `value` | string | *(required)* | Secret value to write. Masked immediately, before login. |
| `vault-addr` | string | `http://k8s-openbao.openbao.svc:8200` | OpenBao address. |

```yaml
- id: read
  uses: mattjmorrison-homelab/actions-tofu/read-output@<commit-sha>
  with:
    state-key: admin-discord/terraform.tfstate
    output-name: webhook_urls
    map-key: github-actions
- uses: mattjmorrison-homelab/actions-openbao/write-secret@<commit-sha>
  with:
    role: ui-hdmi-switch-discord
    kv-path: homelab/ui-hdmi-switch/discord-webhook-url
    value: ${{ steps.read.outputs.value }}
```
