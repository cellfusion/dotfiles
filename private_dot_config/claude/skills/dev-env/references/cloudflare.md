# Multi-Account Operations for Cloudflare

Multiple Cloudflare accounts are utilized across projects. Switching occurs across two distinct layers:

| Layer | Decision | Configuration Scope |
|---|---|---|
| 1Password shell plugin | Which API token to authenticate with | Project directory |
| `CLOUDFLARE_ACCOUNT_ID` | Which account to operate against | herdr session |

Both must be aligned to successfully interact with the intended account. If only one is changed, a mismatch between the token and account ID causes `wrangler` to return an authentication error.

## 1. Authentication (1Password shell plugin)

In `~/.op/plugins.sh`, `wrangler` is aliased to `op plugin run -- wrangler`. Rather than keeping tokens in environment variables, each command execution pulls the token from 1Password.

Assign the token to use per project:

```bash
cd <project-root>
op plugin init wrangler
# Select "Use automatically when in this directory or subdirectories"
```

The assigned account's token will now automatically be used in that directory and its subdirectories.

- Configured items are tracked in `~/.op/plugins/used_items/wrangler.json`.
- `op plugin inspect wrangler` and `op plugin clear wrangler` require interactive I/O and cannot be executed directly from an agent's Bash tool. Ask the user to run `! op plugin inspect wrangler`.

## 2. Target Account (AI Environment)

`CLOUDFLARE_ACCOUNT_ID` and `WRANGLER_HOME` switch per AI environment (`$HERDR_SESSION`). Definitions reside in `[[data.environments]]` of `~/.config/chezmoi/private-data.toml`, where the first item is primary.

| Environment | Source of CLOUDFLARE_ACCOUNT_ID | WRANGLER_HOME |
|---|---|---|
| First (primary) | `cloudflareAccountId` of 1st `[[data.environments]]` | `~/.config/.wrangler` |
| Second onward | Respective `cloudflareAccountId` | `~/.config/.wrangler-<session>` |

`WRANGLER_HOME` is isolated so that wrangler login state and caches do not mix across accounts.

The distributed file is at `~/.config/zsh/agent-environments.zsh`. Its source is chezmoi's `private_dot_config/zsh/agent-environments.zsh.tmpl`, where account IDs and environment names are populated from `private-data.toml` rather than hardcoded. Refer to `herdr.md` for steps on adding environments.

## Adding a New Account

1. Create an API token item in 1Password.
2. Navigate to the project directory used with that account, and run `op plugin init wrangler`.
3. Add `cloudflareAccountId` in the corresponding `[[data.environments]]` block of `~/.config/chezmoi/private-data.toml`. If adding a whole new environment, add a new block.
   Because this is outside the repository, neither IDs nor environment names enter version control.
4. Run `chezmoi init` to regenerate `chezmoi.toml`.
5. `chezmoi apply` is executed by the user.

## Pre-Deployment Verification

```bash
echo $CLOUDFLARE_ACCOUNT_ID
wrangler whoami
```

`wrangler whoami` prompts for 1Password biometric authentication (Touch ID). Because executing this from an agent's Bash tool hangs on the biometric prompt, ask the user to run it with `!`.
