# Secret Handling

As a general rule, never store tokens in plain text in files. Retrieve them from 1Password.

## Choosing the Method

| Method | When to Use | Example |
|---|---|---|
| Shell plugin | When invoking supported CLIs (Default) | `wrangler`, `aws`, `stripe` |
| `op run --env-file` | Injecting multiple environment variables at once; tools not supported by plugins | `op run --env-file=.env -- pnpm dev` |
| `op read` | When needing a one-off value | `curl -H "Authorization: Bearer $(op read op://...)"` |
| `op inject` | Generating config files from templates | `op inject -i config.tpl -o config.json` |

When in doubt, use shell plugins. The values do not linger in environment variables or files, making it the most leak-resistant approach.

## Shell Plugin (Default)

`wrangler`, `aws`, and `stripe` are configured in `~/.op/plugins.sh`. Authentication is intercepted simply by invoking the CLI.

Check whether a CLI is supported using `op plugin list`. Directory-specific assignment methods are detailed in `cloudflare.md`.

## op run --env-file

Write only references in `.env`, never the raw values:

```
CLOUDFLARE_API_TOKEN=op://Vault/item/field
DATABASE_URL=op://Vault/item/field
```

```bash
op run --env-file=.env -- pnpm dev
```

Since this `.env` contains only references, it can be committed. However, be aware that vault and item names will be visible.

## op read

Use only when a value is needed in a single shell command line. Expand it in place without assigning to a persistent variable so that the value does not linger in shell history or process listings.

## op inject

Generated files will contain plain text values. Add them to `.gitignore` and delete them once finished.

## Things Never to Do

- Writing `export CLOUDFLARE_API_TOKEN=<value>` in zshrc or `herdr-sessions/*.zsh`. These are managed by chezmoi and tracked in git.
- Writing actual secret values into `.env`.
- Hardcoding the value for `wrangler secret put` as a command line argument (persists in shell history).
- Outputting `op read` results in agent response bodies (persists in session logs).
