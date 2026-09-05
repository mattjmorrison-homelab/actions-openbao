# actions-openbao

A single reusable GitHub Actions composite action: logs into OpenBao via
this pod's own Kubernetes ServiceAccount identity, fetches one KV secret,
masks it, and exports it as an env var for the rest of the job.

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
| `role` | string | *(required)* | OpenBao Kubernetes-auth role to log in as. |
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

**Pin to a commit SHA, not a branch** -- this org requires
`sha_pinning_required` on every `uses:` reference. Get the current SHA
with:

```sh
gh api repos/mattjmorrison-homelab/actions-openbao/commits/main --jq '.sha'
```

No automation keeps these pins current today; update every caller's pin
manually after any change here that should actually take effect.
