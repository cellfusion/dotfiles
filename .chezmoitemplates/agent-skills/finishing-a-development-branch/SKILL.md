---
name: finishing-a-development-branch
description: >-
  Finish a development branch by verifying the result, determining repository ownership, presenting
  merge/push/retain choices, executing only the selected action, and cleaning up only owned resources.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Finish a Development Branch

This is a parent-only finalizer. Use it after implementation and review artifacts are available. The
parent chooses how to integrate the work; it does not invent missing implementation or verification
results. Child handoff artifacts and fresh verification output are the sources of truth.

**Core sequence:** verify, inspect ownership, present choices, execute the selected action, verify
the result, then clean up only resources owned by this run.

## Step 1: verify before offering integration choices

Run the project's known verification commands. Do not blindly invoke a command that is unavailable
in the current runtime. Prefer the repository's documented test/build/lint commands and the
`verification-before-completion` skill's evidence contract.

Typical checks, when applicable:

- project test suite
- build or type check
- lint or static analysis
- security or pre-commit review
- regression checks for the changed behavior

For every command, record the exact command, exit code, failure count, and the working tree it
verified. Do not call a previous run evidence for the current tree. If a command is unavailable,
record `not_run` with the reason instead of inventing a result.

If any required check fails, stop and report the failure. Do not show the integration menu. If the
repository has an explicit required review command, run it only when the current runtime supports
it and the user has not prohibited it.

Before integration, independently inspect:

```bash
git status --short --branch
git diff --stat
git diff --check
```

Do not create a commit automatically. If uncommitted changes remain, stop and ask whether to commit
them. A Conventional Commit message may be proposed, but the user must authorize the commit.
Never include unrelated existing changes in the proposed commit.

## Step 2: determine repository and worktree ownership

Capture these values before changing directories:

```bash
CALLER_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(cd "$(git rev-parse --git-dir)" 2>/dev/null && pwd -P)
GIT_COMMON=$(cd "$(git rev-parse --git-common-dir)" 2>/dev/null && pwd -P)
WORKTREE_PATH=$(git rev-parse --show-toplevel)
BRANCH=$(git branch --show-current)
```

Use run metadata from `using-git-worktrees`, MAD, Herdr, or the native tool to determine ownership.
Do not infer ownership only from a directory name. A linked worktree can be user-owned even when it
is under `.worktrees/`.

Classify the environment:

| State | Integration choices | Cleanup |
|---|---|---|
| Main checkout (`GIT_DIR == GIT_COMMON`) | merge, push/PR, retain | no worktree cleanup |
| Owned linked worktree on a branch | merge, push/PR, retain | cleanup only after successful integration and explicit cleanup choice |
| External linked worktree | push/PR, retain | never remove it |
| Detached HEAD | push as a new branch, retain | never remove it unless ownership is proven |

If ownership or base branch is unknown, stop and ask. Do not guess `main` or `master`.

## Step 3: establish the base branch

Determine the branch from the plan, task metadata, upstream configuration, or explicit user input.
Verify that it is an ancestor or otherwise a valid integration target before presenting merge choices.
If it cannot be established, ask:

> Which branch should receive this work?

Do not merge into a guessed base.

## Step 4: present choices and wait

For a normal checkout or an owned branch worktree, present exactly these choices:

```text
Verification is complete. How should this work be integrated?

1. Merge locally into <base-branch>
2. Push <feature-branch> and create a Pull Request
3. Leave the branch and worktree in place
```

For detached HEAD or an external worktree, present:

```text
This workspace is detached or externally managed. How should this work be integrated?

1. Push it as a new branch and create a Pull Request
2. Leave it in place
```

Do not include a discard option in the normal menu. Wait for an explicit selection. Do not commit,
merge, push, delete a branch, archive a workspace, or remove a worktree before the selection.

## Step 5: execute the selected action

### Choice 1: local merge

Perform integration from the main checkout, not from the feature worktree:

```bash
MAIN_ROOT=$(git -C "$GIT_COMMON" rev-parse --show-toplevel)
cd "$MAIN_ROOT"
git switch <base-branch>
git merge <feature-branch>
```

Do not run `git pull` automatically. If the base branch is behind its remote, report that fact and
ask whether to fetch/update it. Do not force-push or force-merge.

After a successful merge, run the required verification commands on the merged checkout. If they
fail, stop and retain the branch and worktree. Do not delete anything after a failed merge check.

Only after successful verification may the user be asked whether to delete the merged branch and
owned worktree. Branch deletion is destructive and must not be bundled silently into the merge.

### Choice 2: push and create a Pull Request

Push only the selected branch:

```bash
git push -u origin <feature-branch>
```

For detached HEAD, use an explicitly chosen branch name:

```bash
git push origin HEAD:refs/heads/<new-branch>
```

Create the Pull Request only when the user selected this option and the forge CLI is available. Use
the repository's PR template and base branch. Report the URL. Retain the worktree for follow-up
feedback. Do not remove it after opening the PR.

### Choice 3: retain

Report the branch, worktree path, verification evidence, ownership, and the next command the user
can run. Do not clean up.

### Explicit discard request

Discard is a separate destructive workflow. Accept it only after the user explicitly requests it.
Show the complete deletion set:

```text
The following will be deleted:
- branch: <branch>
- commits: <commit list>
- owned worktree: <path>

Type `discard` exactly to confirm.
```

Wait for the exact word `discard`. If confirmed, move outside the worktree, remove only owned
resources, and force-delete the branch. If confirmation is absent or differs, retain everything.

## Step 6: cleanup owned resources only

Cleanup is allowed only after successful local merge plus post-merge verification, or after exact
`discard` confirmation. Never clean after push/PR or retain.

Use recorded ownership and backend:

- Herdr: `herdr worktree remove --workspace <workspace-id> --force`.
- Native workspace: use the native cleanup operation.
- Git worktree created by this run: from outside it, run `git worktree remove <path>` and prune
  stale registrations only when owned.
- Caller-owned or host-owned worktree: leave it untouched.

If cleanup fails, retain all metadata and report the path and failure. Do not retry destructively.

## Chezmoi repositories

`chezmoi apply` reads the main source directory returned by `chezmoi source-path`. For a chezmoi
repository:

1. Commit only the intended changes in the feature worktree after explicit approval.
2. Merge into the main source checkout if the user selects local merge.
3. Run `chezmoi diff` from the main source checkout.
4. Ask for explicit permission before running `chezmoi apply`.

Never apply from an unmerged worktree and never claim that apply happened without fresh evidence.

## Completion record

Report:

```text
verification: <commands, exit codes, and evidence paths>
base: <branch>
choice: <merge|push-pr|retain|discard>
branch: <branch or detached HEAD>
worktree: <absolute path or none>
ownership: <owned|external|main-checkout>
cleanup: <removed|retained|not-owned|failed>
```
