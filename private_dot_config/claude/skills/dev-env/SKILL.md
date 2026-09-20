---
name: dev-env
description: >-
  Operational procedures specific to this development environment. Covers Cloudflare account
  switching, CLI authentication and secret retrieval via 1Password, and environment variables
  per AI environment (herdr / Paseo). Read before tasks touching deployments, credentials,
  environment variables, or account switching. Can also be invoked manually with /dev-env.
---

# Development Environment Operations

Documenting operational procedures for this machine (macOS / herdr / chezmoi). Rather than generic technical knowledge, this guides practical operations in this specific setup.

## Which Chapter to Read

| Situation | Reference File |
|---|---|
| Deploying to Cloudflare or switching accounts | `references/cloudflare.md` |
| Requiring API tokens or credentials | `references/secrets.md` |
| Configuring environment variables per AI environment | `references/herdr.md` |

## Common Prerequisites

- Configuration under `~/.config` is managed by chezmoi. Always edit inside `~/.local/share/chezmoi/`; `chezmoi apply` is executed by the user.
- Never store secrets in plain text files. Retrieve them from 1Password.
- Before running actions that alter the environment (account switching, plugin configuration), verify what is currently active.
