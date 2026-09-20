---
name: using-git-worktrees
description: >-
  Use before executing an implementation plan or developing features in isolation
  from the current workspace. Detects whether the session is already isolated, creates
  a worktree if necessary, and completes dependency installation and baseline tests.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Setting Up an Isolated Workspace

## Overview

Perform implementations in an isolated workspace. If the harness provides worktree management tools, prefer those; fall back to `git worktree` only when unavailable.

**Core**: First detect if already isolated. Next use native tools. Finally fall back to git. Never fight the harness.

**Announce at start**: "Preparing isolated workspace using using-git-worktrees."

## Step 0: Detect Existing Isolation

**Before creating anything, verify whether the current directory is already an isolated workspace.**

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
BRANCH=$(git branch --show-current)
```

**Submodule guard**: `GIT_DIR != GIT_COMMON` evaluates to true inside submodules as well. Before concluding "already in a worktree", verify it is not a submodule:

```bash
# If a path returns, this is a submodule, not a worktree. Treat as normal repository
git rev-parse --show-superproject-working-tree 2>/dev/null
```

**If `GIT_DIR != GIT_COMMON` (and not a submodule)**: You are already inside a linked worktree. Do not create another worktree. Perform herdr verification and reporting below before advancing to Step 2.

**Under herdr management (`$HERDR_ENV` is `1`)**: Verify whether that worktree is opened as a workspace. An unopened worktree lacks a terminal, making agent actions invisible to humans. If `herdr worktree list` fails, skip this check and proceed.

```bash
ws=$(herdr worktree list --cwd "$(pwd -P)" \
  | jq -r --arg p "$(pwd -P)" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
```

If `ws` is empty, open it as a workspace:

```bash
out=$(herdr worktree open --path "$(pwd -P)" --no-focus)
ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
```

If already opened, reuse `ws` obtained from `herdr worktree list`.

If `$HERDR_ENV` is not `1`, skip this check entirely.

Report along with branch state. Under herdr management, include workspace ID (`$ws`):

- On branch: "Already in isolated workspace `<path>` (branch `<name>`, workspace `<id>`)."
- Detached HEAD: "Already in isolated workspace `<path>` (detached HEAD, managed externally). Branch creation deferred to finish step."

Once reported, advance to Step 2.

**If `GIT_DIR == GIT_COMMON` (or a submodule)**: You are in a normal checkout. Advance to Step 1.

## Step 1: Create Isolated Workspace

Try the 3 methods in this order of precedence:

### 1a. Herdr Worktree (Top priority under herdr management)

If `$HERDR_ENV` is `1`, try this first:

```bash
out=$(herdr worktree create --workspace "$HERDR_WORKSPACE_ID" --branch "<branch>" --base HEAD --no-focus)
path=$(printf '%s' "$out" | jq -r '.result.worktree.path')
ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
cd "$path"
```

Worktrees created via herdr become workspaces accessible to humans, allowing external visibility of the working tree and agent progress. Because worktrees created via harness tools lack terminals, prefer herdr worktrees first.

- **Always pass `--workspace`.** If omitted, the user's currently focused workspace becomes the reference.
- **Do not pass `--path`.** herdr creates it under `~/.herdr/worktrees/<repo>/<branch>`. Worktrees created in 1a do not need the directory determination or ignore checks below.
- If `path` or `ws` is empty or `null`, delegation failed. If `ws` is non-empty, clean up with `herdr worktree remove --workspace "$ws" --force` before falling back to 1b. If `ws` is empty or `null`, cleanup cannot proceed; report and fall back to 1b.

Include path, branch, and workspace ID in report. Advance to Step 2.

### 1b. Native Worktree Tools

If tools like `EnterWorktree`, `/worktree` command, or `--worktree` flag are available, use them. Advance to Step 2.

Native tools manage placement, branch creation, and cleanup internally. Using `git worktree add` when native tools are present creates state invisible to the harness.

Advance to 1c only when 1b is unavailable.

### 1c. Create with git worktree

#### Directory Determination

Decide in this order of precedence. Explicit user instruction is always highest priority:

1. **Check if instructions specify a worktree directory**. If so, use it without asking.
2. **Search for existing worktree directories in the project**:
   ```bash
   ls -d .worktrees 2>/dev/null     # Preferred (hidden directory)
   ls -d worktrees 2>/dev/null      # Alternative
   ```
   If found, use it. If both exist, choose `.worktrees`.
3. **If no other hints exist**, default to `.worktrees/` at repository root.

#### Safety Check (Only for in-project directories)

**Before creating a worktree in 1c, always verify the directory is ignored**:

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

**If not ignored**: Add to `.gitignore` and commit before proceeding, preventing the entire worktree contents from entering the repository.

#### Creation

```bash
path="$LOCATION/$BRANCH_NAME"
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

**On sandbox failure**: If `git worktree add` fails due to permission errors, inform the user that sandbox restrictions prevent worktree creation, and proceed in the current directory. Perform setup and baseline tests in place.

## Step 2: Project Setup

**If the repository has `.config/wt.toml`, delegate to worktrunk.** Unversioned file copying (based on `.worktreeinclude`) and dependency installation are defined there:

```bash
if [ -f "$(git rev-parse --show-toplevel)/.config/wt.toml" ] && command -v wt >/dev/null 2>&1; then
  wt hook pre-start
fi
```

`wt hook pre-start` works regardless of who created the worktree (herdr or `git worktree add`). **Use `pre-start`.** `post-start` runs in background and returns immediately, causing Step 3's baseline tests to run against an incomplete setup.

**For repositories without `.config/wt.toml`**, detect and run appropriate setup commands:

```bash
if [ -f package.json ]; then npm install; fi
if [ -f Cargo.toml ]; then cargo build; fi
if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
if [ -f pyproject.toml ]; then poetry install; fi
if [ -f go.mod ]; then go mod download; fi
```

If untracked files like `.env` are required but manually distributed each time, suggest adding `.worktreeinclude` and `.config/wt.toml` to the repository.

## Step 3: Check Baseline

Verify the workspace starts from a clean state by running tests:

```bash
npm test / cargo test / pytest / go test ./...
```

**If tests fail**: Report failures and ask the user whether to proceed or investigate.

**If tests pass**: Report readiness:

```
worktree: <full-path>
tests: <N> passed, 0 failed
Ready to begin implementing <feature-name>
```

In projects without tests (dotfiles, configuration repositories, etc.), verify that `git status` is clean instead.

## Notes for Chezmoi Repositories

`chezmoi apply` reads the **chezmoi source directory (path returned by `chezmoi source-path`, defaults to `~/.local/share/chezmoi`)**, not the checked-out branch. Edits in a worktree (e.g. `~/.local/share/chezmoi/.worktrees/feat-x`) will not be reflected in `chezmoi apply` directly.

- Implement and commit in the worktree.
- Merge into the main checkout before reflecting via `chezmoi diff` / `chezmoi apply` (apply requires explicit user confirmation).

## Quick Reference

| Situation | Action |
|---|---|
| Already inside linked worktree | Do not create (Step 0) |
| Inside worktree but not open as workspace | Open via `herdr worktree open` (Step 0) |
| Inside submodule | Treat as standard repo (Step 0 guard) |
| Under herdr management (`HERDR_ENV=1`) | Create via `herdr worktree create` (Step 1a) |
| Native worktree tool available | Use native tool (Step 1b) |
| No native tools | Create with git worktree (Step 1c) |
| `.worktrees/` exists | Use it (verify ignore) |
| `worktrees/` exists | Use it (verify ignore) |
| Both exist | Choose `.worktrees/` |
| Neither exists | Check instructions; default is `.worktrees/` |
| Directory not ignored | Add to `.gitignore` and commit |
| Creation permission error | Assume sandbox restriction and work in current dir |
| Baseline tests fail | Report failures and ask for guidance |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Doesn't look like a worktree" | Run Step 0. Neither harness isolation nor submodules can be reliably identified by sight |
| "`git worktree add` creates the same thing" | Only creates a working tree without a terminal. Agent progress remains invisible to humans |
| "`git worktree add` is faster" | Native tools manage placement, branching, and cleanup. Bypassing leaves untracked state in the harness |
| "Worktree directories are already ignored anyway" | Run `git check-ignore`. If not ignored, the entire worktree tree enters the repository |
| "Clean workspace so baseline will pass" | A polluted baseline obscures all subsequent failures. Run baseline tests first |
| "Chezmoi repositories can apply from worktrees" | Apply reads the source directory. Changes are reflected only after merging into main checkout |
