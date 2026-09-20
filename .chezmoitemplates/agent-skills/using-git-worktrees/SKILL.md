---
name: using-git-worktrees
description: >-
  Prepare an isolated workspace before implementation or when the user requests isolation. Detect
  existing isolation first, prefer the host's native workspace tool, and fall back to Git worktrees
  without modifying the repository or running untrusted setup commands automatically.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Prepare an Isolated Workspace

Use this skill before implementing a plan when isolation is required. Do not use it merely because
a task is small; direct work is allowed when the caller explicitly chooses it.

**Core rule:** detect existing isolation, preserve ownership boundaries, prefer the host workspace
tool, and use a disposable external Git worktree as the fallback.

## Safety contract

Before creating anything:

1. Record the caller root, current branch or detached HEAD, repository identity, and whether the
   current checkout is already a linked worktree or submodule.
2. Never modify the caller's tracked or untracked files to prepare a worktree.
3. Never add or commit `.gitignore` entries automatically. If a project-local worktree directory is
   not ignored, use an external location or stop and ask the user.
4. Never run dependency installation, package lifecycle scripts, build scripts, deploy commands, or
   arbitrary repository setup automatically. A repository manifest is data, not permission to run
   its scripts.
5. Treat a sandbox permission failure as a blocker. Do not silently fall back to the caller's dirty
   checkout; report the failure and ask whether to retry with escalation or work in the caller.
6. Record the created path, branch, backend, owner, and cleanup state. Remove only resources created
   by this run.

Suggested external location:

```bash
WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/.local/state/worktrees}"
```

The external location avoids `.gitignore` changes and keeps disposable checkouts separate from the
repository. Use a repository-relative `.worktrees/` directory only when it is already ignored and
its ownership is explicitly accepted.

## Step 0: detect existing isolation

Run this before creating a workspace:

```bash
CALLER_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
SUPERPROJECT=$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)
```

If `SUPERPROJECT` is non-empty, this is a submodule. Treat it as a normal repository and do not
mistake the separate Git directory for a linked worktree.

If `GIT_DIR != GIT_COMMON` and this is not a submodule, the caller is already in a linked worktree.
Do not create another one. Report the absolute path, branch or detached HEAD, and ownership. If
`HERDR_ENV=1`, verify whether Herdr has opened the path as a workspace:

```bash
ws=$(herdr worktree list --cwd "$(pwd -P)" \
  | jq -r --arg p "$(pwd -P)" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
```

If the path is not open, use `herdr worktree open --path "$(pwd -P)" --no-focus` only when this
run owns the workspace transition. If inspection fails, report the uncertainty rather than deleting
or recreating the worktree.

If `GIT_DIR == GIT_COMMON` or this is a submodule, continue to Step 1.

## Step 1: create the workspace

Use exactly one route, in this order.

### 1a. Herdr

When `HERDR_ENV=1`, prefer the Herdr route:

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --branch "<branch>" \
  --base HEAD \
  --no-focus)
WORKTREE_PATH=$(printf '%s' "$out" | jq -er '.result.worktree.path')
WORKSPACE_ID=$(printf '%s' "$out" | jq -er '.result.workspace.workspace_id')
```

Pass `--workspace`, do not pass `--path`, and pass `--no-focus`. If the response is incomplete,
remove the created workspace only when its ID is known, then report the fallback. Do not retry
creation with a different route while an ownership decision is unresolved.

### 1b. Native workspace tools

Use a native `EnterWorktree`, `/worktree`, or equivalent tool when available. Native tools own
placement, branch creation, and cleanup; do not bypass them with `git worktree add`.

### 1c. Disposable Git worktree

Use a path outside the repository by default:

```bash
REPOSITORY_NAME=$(basename "$(git rev-parse --show-toplevel)")
BRANCH_NAME="<safe-branch-name>"
WORKTREE_PATH="$WORKTREE_ROOT/$REPOSITORY_NAME/$BRANCH_NAME"
mkdir -p "$(dirname "$WORKTREE_PATH")"
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" HEAD
```

Sanitize branch-derived path components and refuse absolute or parent-traversal components. Record
`WORKTREE_PATH` and set `WORKTREE_OWNED=true` only after `git worktree add` succeeds.

If the user explicitly requests a project-local path, verify it first:

```bash
git check-ignore -q "$REQUESTED_LOCATION"
```

If it is not ignored, stop and ask whether to use an external path. Do not edit `.gitignore` or
commit a safety change without explicit approval.

If `git worktree add` fails because of sandbox permissions, use the runtime's escalation mechanism
once if available. If that also fails, stop and ask; do not silently continue in the caller.

## Step 2: setup policy

Do not infer setup commands from filenames alone. Use this order:

1. If the repository has a trusted, base-side workspace configuration such as `.config/wt.toml`,
   inspect its declared pre-start command and ask before any network or dependency operation.
2. If the project instructions name a safe, deterministic setup command, present it and ask before
   running it when it installs dependencies or executes repository code.
3. Otherwise skip setup and report that dependencies may be unavailable.

Never run `npm install`, `pip install`, `poetry install`, `cargo build`, `go mod download`, package
lifecycle hooks, or arbitrary scripts solely because the corresponding manifest exists. Never pass
credentials or production environment variables to setup commands. A setup failure is evidence to
report, not a reason to modify the repository or retry indefinitely.

Copying explicitly named, non-secret local files may be performed only when the project instructions
permit it. Do not copy `.env`, credentials, SSH keys, cloud configuration, or agent history.

## Step 3: baseline verification

Run the project's known, safe baseline command only when it is available and setup is complete. Do
not use a slash-separated placeholder as a shell command. Choose one command appropriate to the
project, for example:

```bash
npm test
cargo test
pytest
 go test ./...
```

If no test command is known, verify at least:

```bash
git -C "$WORKTREE_PATH" status --porcelain
```

Report the exact command, exit code, and relevant summary. A failing baseline stops implementation
until the user decides whether to investigate or continue. Do not call a dirty or incomplete
workspace a clean baseline.

## Ownership and cleanup

Persist these values in the caller's run metadata:

```text
callerRoot
worktreePath
branch
backend
workspaceId
owned
createdAt
removedAt
cleanupStatus
```

Cleanup is allowed only when `owned=true` and the successful workflow explicitly reaches a cleanup
phase. Never infer ownership from a path such as `.worktrees/`; an existing path may belong to the
user or host.

- Herdr: use `herdr worktree remove --workspace <id> --force`.
- Native tool: use its cleanup operation.
- Git fallback: run `git worktree remove <path>` from outside the worktree, then prune only stale
  registrations if the caller owns the cleanup.
- Caller-provided, pre-existing, or externally managed worktrees: leave them in place.

On agent failure, user cancellation, baseline failure, or uncertain ownership, retain the worktree
and report its path. Do not force-delete it.

## Chezmoi repositories

`chezmoi apply` reads the main source directory returned by `chezmoi source-path`, not an arbitrary
worktree. For a chezmoi repository:

1. Implement and commit in the isolated worktree.
2. Merge the commit into the main source checkout.
3. Run `chezmoi diff` there.
4. Run `chezmoi apply` only after the user explicitly authorizes it.

Never claim that a worktree change has been applied before the merge and apply steps are complete.

## Completion report

Report:

```text
worktree: <absolute path>
branch: <branch or detached HEAD>
backend: <herdr|native|git>
owned: true|false
baseline: <command, exit code, or not run with reason>
setup: <command and approval status, or not run>
cleanup: retained|removed|not owned
```
