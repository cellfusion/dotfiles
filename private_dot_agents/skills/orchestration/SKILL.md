---
name: orchestration
description: >-
  Supervise Orca workers, threaded messages, blocking decisions, task dispatch, waits, and DAGs only
  when the user explicitly requests Orca coordination or the task explicitly operates Orca runtime
  state. Generic multi-agent coordination, handoff, or parallel tasks use OMP, not this skill.
---

# Orca Orchestration

This chezmoi-managed discovery leaf loads the runtime guide from the selected Orca binary; it is not
a fork of the guide. Engage it only for an explicit Orca coordination request or an explicitly
identified Orca-runtime operation. Generic decomposition, supervised agents, DAGs, or handoff do not
select Orca: use OMP internal delegation and `multi-agent-development` by default. Herdr owns
independent CLI/user interaction; Worktrunk owns hidden write isolation.

For an authorized full Orca ownership handoff, terminal/worktree/browser operation, use `orca-cli`.
Orca coordination requires actual Orca runtime state; do not simulate it with a non-Orca task tool.
Conversely, do not call Orca to obtain state for an ordinary OMP task.

## Resolve the CLI for this session

Choose the executable once and reuse it for every later command:

- If `ORCA_CLI_COMMAND` is set, use its value. Orca exports this for managed WSL sessions.
- Otherwise, in a dev checkout whose session exposes `ORCA_DEV_REPO_ROOT`, use `orca-dev`.
- Otherwise, on Linux outside an Orca-managed terminal, use `orca-ide`. Never run bare `orca`
  there: it normally resolves to the GNOME screen reader and starts speech on the user's machine.
- Otherwise, use `orca`.

Below, `ORCA` is a placeholder for that executable. Substitute it; do not create a shell variable or
run `ORCA` literally. If it cannot run, report the exact error and stop. Do not switch executables.

## Load the version-matched guide before Orca commands

```text
ORCA skills get orchestration
```

This loads the compact guide for the selected binary. For conditional gates such as remote
placement, release recovery, or expanded DAG work, read only the reference the guide names:

```text
ORCA skills get orchestration --reference references/<file>.md
```

Use `--references` to list names. If the binary rejects `--reference`, use
`ORCA skills get orchestration --full` and read the named bundled reference before acting.
Prefer `--json`. Read live `--help` for uncovered commands/flags. If Orca is not running during an
authorized Orca task, use `ORCA open --json` and retry. For `runtime_access_denied`, retry using the
runtime's escalation mechanism, not open/restart. If `skills get` is unknown, report the needed
Orca update; use help only for read-only discovery and never guess APIs.
