---
name: orca-cli
description: >-
  Operate Orca worktrees, terminals, repos, automations, artifacts, browser, and skill sharing only
  when the user explicitly requests Orca or the task explicitly operates on Orca-managed state.
  Do not trigger for generic handoff, child worktrees, parallelism, or spawning another agent.
---

# Orca CLI

This chezmoi-managed discovery leaf preserves version-matched guide loading from Orca. It does not
vendor or replace Orca's runtime guide. Use it only for an explicit Orca request or an explicitly
identified Orca-managed operation. Ordinary delegation stays inside OMP; independent CLI interaction
uses Herdr, and hidden write isolation uses Worktrunk through `using-git-worktrees`. Generic
“handoff”, “another worktree”, or “spawn an agent” does not authorize an Orca route.

## Resolve the CLI for this session

Choose the executable once and reuse it for every later command:

- If `ORCA_CLI_COMMAND` is set, use its value. Orca exports this for managed WSL sessions.
- Otherwise, in a dev checkout whose session exposes `ORCA_DEV_REPO_ROOT`, use `orca-dev`.
- Otherwise, on Linux outside an Orca-managed terminal, use `orca-ide`. Never run bare `orca`
  there: it normally resolves to the GNOME screen reader and starts speech on the user's machine.
- Otherwise, use `orca`.

Below, `ORCA` is a placeholder for that executable. Substitute it; do not create a shell variable or
run `ORCA` literally. If it cannot run, report the exact error and stop. Do not fall through to
another executable that could target a different build.

## Load the version-matched guide before Orca commands

```text
ORCA skills get orca-cli
```

Prefer `--json`. Read that guide and live `--help` for commands/flags it does not cover. If Orca is
not running during an authorized Orca task, use `ORCA open --json` and retry. If the error is
`runtime_access_denied`, the sandbox blocked the connection: retry with the runtime's escalation
mechanism rather than opening or restarting Orca. If `skills get` is unknown, explain that updating
Orca restores the guide; use help only for read-only discovery and do not guess APIs.
