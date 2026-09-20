---
name: finishing-a-development-branch
description: >-
  Use when implementation is finished to determine how to integrate this work.
  Runs tests and verifications, evaluates environment, presents options, executes
  selected action, and cleans up. Entrypoint for "done", "merge", or "create PR".
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Finishing a Development Branch

## Overview

This is a parent-exclusive finalizer. After MAD's `delivery` confirms the accepted attempt's final review and verification records are `ok`, only the parent confirms integration method via `[ask-user]` and executes the chosen merge / push / keep action. The parent does not generate implementation, review, or verification text; the authoritative source is the absolute paths recorded by delivery children in `handoff.json`.

**Core**: Verify -> evaluate environment -> present options -> execute chosen option -> clean up.

**Announce at start**: "Finishing this work using finishing-a-development-branch."

## Step 1: Pass Verification

1. Run the project's test suite (`npm test` / `cargo test` / `pytest` / `go test ./...`)
2. Run `/verify` (runs build, typecheck, lint, test, and debug statement audit together)
3. Run `/pre-commit-review` (security and code quality checks)

**If failures occur, stop and report.** Present the menu only after reaching green.

```
Tests are failing (<N> failures). Must be resolved before finishing:

[Failure details]
```

Stop similarly if `/pre-commit-review` returns `CRITICAL`.

**Once all pass**, advance to Step 2.

If uncommitted changes remain, commit using Conventional Commits (`<type>: <description>`, 1 commit per logical change) before advancing.

## Step 2: Determine Environment

```bash
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
# Capture before changing directories in Step 5
WORKTREE_PATH=$(git rev-parse --show-toplevel)
```

Determines which menu to display and how cleanup is handled:

| State | Menu | Cleanup |
|---|---|---|
| `GIT_DIR == GIT_COMMON` (standard repository) | 3 options | No worktree |
| `GIT_DIR != GIT_COMMON`, on branch | 3 options | Based on provenance (Step 6) |
| `GIT_DIR != GIT_COMMON`, detached HEAD | 2 options (no merge) | Managed externally; leave untouched |

## Step 3: Determine Base Branch

The base branch is where this work branched from. Usually documented in plans, conversations, or upstream branch tracking. If uncertain, ask:

> "I believe this branch diverged from <guess>, is that correct?"

Confirm before merging; merging into the wrong base is costly to revert.

## Step 4: Present Options

**Standard repository and worktree on branch — present these 3 choices verbatim**:

```
Implementation complete. How would you like to proceed?

1. Merge locally into <base-branch>
2. Push and create a Pull Request
3. Keep the branch as is (handle manually)

Which do you prefer?
```

**Detached HEAD — present these 2 choices verbatim**:

```
Implementation complete. Currently in detached HEAD (externally managed workspace).

1. Push as a new branch and create a Pull Request
2. Keep as is (handle manually)

Which do you prefer?
```

Present the menu exactly as written. **Do not include options to discard work.** Discarding happens only upon explicit user request (detailed below). Await answer. The integration decision belongs to the user.

## Step 5: Execute Chosen Action

### Option 1: Merge Locally

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"

# Merge first; delete nothing until verified
git checkout <base-branch>
git pull
git merge <feature-branch>

# Run tests on merge result
<test command>
```

If tests fail on the merge result, stop, leave worktree and branch intact, and investigate. Because it hasn't been pushed, the merge is local and can be undone.

Once tests pass on the merge result, clean up the worktree (Step 6) and delete the branch:

```bash
git branch -d <feature-branch>
```

### Option 2: Push and Create PR

```bash
git push -u origin <feature-branch>
# From detached HEAD, specify remote branch name:
# git push origin HEAD:refs/heads/<new-branch>
```

Create a PR against `<base-branch>`. Use forge CLI if available, otherwise output the PR creation URL shown during push. Follow PR templates and repository conventions. Report the URL to the user.

**Keep the worktree.** Address PR review feedback within that worktree.

### Option 3: Keep As-Is

Report: "Retaining branch <name>. Worktree located at <path>."

### If User Requests Discard

This path exists only in response to explicit instructions to discard work. Confirm beforehand:

```
This will permanently delete:
- Branch <name>
- Commits: <commit-list>
- Worktree: <path>

Please type 'discard' to confirm.
```

Wait for the **exact word**. Once received:

```bash
MAIN_ROOT=$(git -C "$(git rev-parse --git-common-dir)/.." rev-parse --show-toplevel)
cd "$MAIN_ROOT"
```

Clean up worktree (Step 6) and force-delete the branch:

```bash
git branch -D <feature-branch>
```

## Step 6: Workspace Cleanup

**Execute only for Option 1 and confirmed discards.** Options 2 and 3 always retain worktrees. Both callers have already moved to the main repository root (worktree deletion must be executed outside the worktree). Use `GIT_DIR` / `GIT_COMMON` / `WORKTREE_PATH` captured in Step 2.

**If `GIT_DIR == GIT_COMMON`**: Standard repository; no worktree to clean up.

**If `WORKTREE_PATH` is under `.worktrees/` or `worktrees/`**: Created as part of this workflow; clean up here:

```bash
git worktree remove "$WORKTREE_PATH"
git worktree prune
```

MAD run directories reside outside the working tree, so deleting the worktree does not destroy them.

**If `$HERDR_ENV` is `1` and `WORKTREE_PATH` is under `~/.herdr/worktrees/`**: Worktree created as a herdr workspace. Close the workspace before deleting:

```bash
ws=$(herdr worktree list --cwd "$WORKTREE_PATH" \
  | jq -r --arg p "$WORKTREE_PATH" '.result.worktrees[] | select(.path == $p) | .open_workspace_id // empty')
if [ -n "$ws" ]; then
  herdr worktree remove --workspace "$ws" --force
fi
```

If `ws` is empty, the workspace no longer exists; skip to deleting `git branch`. `herdr worktree remove` also deletes the worktree directory, so `git worktree remove` above is not needed.

**Otherwise**: Workspace owned by host environment; leave intact. Use harness exit tools if available.

## For Chezmoi Repositories

`chezmoi apply` reads the **chezmoi source directory** (returned by `chezmoi source-path`). Changes implemented in a worktree will not be reflected in `chezmoi apply` until merged into the main checkout.

Sequence:
1. Implement and commit in worktree
2. Merge into main checkout via Option 1
3. Inspect changes via `chezmoi diff`
4. **Execute `chezmoi apply` only after obtaining explicit user permission**

## Quick Reference

| Option | Merge | Push | Keep Worktree | Delete Branch |
|---|---|---|---|---|
| 1. Local Merge | Yes | - | - | Yes |
| 2. Create PR | - | Yes | Yes | - |
| 3. Keep As-Is | - | - | Yes | - |
| Discard (explicit only) | - | - | - | Yes (forced) |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Tests passed earlier" | Run tests on the tree you are about to merge into. Green only proves the tree it was run on |
| "Obviously they want to merge" | Integration decisions belong to the user. Present the menu and wait |
| "This feature looks unneeded, suggesting discard" | Menu is complete as written. Discard only when user explicitly asks |
| "'Sure, go ahead and delete' is confirmation" | Only permit deletion when user enters `discard` |
| "PR opened, worktree no longer needed" | PR feedback is resolved in that worktree. Retain until merged |
| "This worktree looks old, deleting too" | Clean up only under `.worktrees/`, `worktrees/`, or `~/.herdr/worktrees/`. Host owns the rest |
| "Merge result test failure is probably flaky" | Merge failures halt everything. Leave branch and worktree intact to investigate |
| "Base is probably main anyway" | Confirm or ask. Merging to the wrong base is costly to undo |
| "Push rejected, force-pushing" | Rejection means remote has advanced. Investigate. Force-push only on explicit user request |
