---
name: using-git-worktrees
description: >-
  Detect existing isolation and record ownership before implementation. Use Herdr for a visible main
  workspace or PR entry and Worktrunk for hidden child write isolation, without automatic hooks or copying.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Choose Worktree Ownership Independently of Agent Execution

Herdr owns visible workspaces and terminals. OMP owns ordinary internal delegation. Worktrunk owns
hidden child write isolation. A pane and a worktree are independent decisions: a CLI conversation
may use an existing cwd; a write-isolated child has no extra pane. Do not make a new environment
merely to run an OMP child. Do not start a second orchestration runtime for ordinary delegation.

## Step 0: detect and record existing isolation

Before creation, inspect:

```bash
CALLER_ROOT=$(git rev-parse --show-toplevel)
GIT_DIR=$(git rev-parse --path-format=absolute --git-dir)
GIT_COMMON=$(git rev-parse --path-format=absolute --git-common-dir)
BRANCH=$(git branch --show-current)
SUPERPROJECT=$(git rev-parse --show-superproject-working-tree)
BASE_SHA=$(git rev-parse --verify 'HEAD^{commit}')
git status --short
git worktree list --porcelain
```

A submodule's separate Git directory does not imply a linked worktree. If already isolated for the
current task, reuse it; do not create another or open a Herdr workspace automatically. A child with
its own write ownership can still need a separate worktree from this parent checkout.

Record repository identity, caller root, branch/detached state, base SHA, owner (`herdr`,
`worktrunk`, or `external`), absolute path, workspace/pane IDs only when they exist, creation/adoption
status, integration state, and liveness. Determine owner from prior metadata and host inspection,
not directory names. Missing/unknown owner is external for cleanup purposes.

For Herdr inspection, read `herdr` and current CLI help, use explicit current workspace/pane IDs or
`--current` where supported, and match the exact checkout path. Never delete/re-create a resource
because inspection failed. Worktrunk visibility in a list does not establish Worktrunk ownership.

## Safety and base prerequisites

Never modify the caller's files or `.gitignore` to prepare isolation. Never auto-copy tracked,
untracked, or ignored changes, `.env`, credentials, SSH/cloud config, or agent history. Child bases
must be committed and resolved to immutable SHA. If required parent work is uncommitted, stop that
dependent dispatch and let the user scope/authorize a commit or narrowly specified non-secret
transfer; do not automatically commit or copy it. Independent work with no such prerequisite can
continue. A dirty parent does not automatically block unrelated children.

Do not run setup, lifecycle scripts, install commands, deploys, network operations, or arbitrary
repository hooks merely because a manifest/config exists. Do not use permission bypasses, force,
clobber, or silent fallback to the caller checkout when creation fails.

## Route A: visible main work

Read `herdr` and live help. Resolve the repository's actual default branch and its committed SHA
from repository metadata; do not guess `main`/`master`. New main work starts from that default
base unless the user specifies another base. Reuse an existing task workspace rather than resetting
it to default or nesting another worktree.

From agent control, create without taking focus:

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" --branch "$NEW_BRANCH" \
  --base "$DEFAULT_BASE_SHA" --no-focus)
WORKTREE_PATH=$(printf '%s' "$out" | jq -er '.result.worktree.path')
WORKSPACE_ID=$(printf '%s' "$out" | jq -er '.result.workspace.workspace_id')
ROOT_PANE_ID=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id')
```

Use returned IDs/path and record owner `herdr`. Validate path, branch, and base before handing off.
If creation returns incomplete information, retain known IDs/paths and report the failure stage and
orphan risk. Do not retry creation, use another backend, or remove partially known resources.

For PR review, use the dedicated shell entry `pr-review [--quick] <PR>`; agents add `--no-focus`.
It creates the base-SHA Herdr review worktree/workspace and starts OMP in its root pane. Prepared
reviews reuse that environment and fixed context. Do not manually checkout PR head, create an
additional pane, or run head-side instructions before the review trust boundary is established.
Head-code execution, if authorized, belongs to a separate hidden Worktrunk checkout.

## Route B: hidden child write isolation

Use Worktrunk only; this route does not create or open any Herdr workspace/tab/pane. Read live
`wt switch --help` and `wt remove --help`. Resolve a unique safe branch and the committed parent
base, check collision/ownership first, then:

```bash
out=$(wt -C "$CALLER_ROOT" switch --create "$CHILD_BRANCH" \
  --base "$BASE_SHA" --no-cd --no-hooks --format json)
WORKTREE_PATH=$(printf '%s' "$out" | jq -er '.path')
```

`--format json` is the actual interface, not `--json`. Read the absolute path from JSON; do not
predict it from the path template. Require `action=created`, `created_branch=true`, and the expected
branch, then verify HEAD equals the recorded base. Record owner `worktrunk`, no workspace/pane ID,
and integration `pending`. The retained `mad-worktree` helper provides this route with ownership
records for bounded task branches.

`--no-cd` leaves the parent cwd alone. `--no-hooks` suppresses user and project hooks, including
terminal launch and arbitrary setup. Keep the configured worktree path template; do not override it
with a second placement convention. Do not use `wt merge` to auto-integrate into default.

## Setup and verification

If setup is required, inspect trusted base-side project instructions and explicitly run only the
approved deterministic procedure in the selected cwd. Network/dependency operations need approval;
do not re-enable hooks as a shortcut. Named non-secret local-file copying also needs scoped approval.
On setup failure retain the resource and evidence.

The parent selects safe baseline/acceptance checks and names the verification owner. Shared writers
skip mid-flight builds/tests/linters/formatters; integration verifies after all writes land. Report
command, cwd, exit code, and summary, or an explicit not-run reason. Existing user-reported failures
are ground truth; do not rerun merely to confirm them. A failing or unavailable baseline is not clean.

## Integration and cleanup

Adopt only scope-checked results with fresh evidence. Integrate into the recorded parent working
branch after authorization, not automatically into default. Commit, merge, push, and apply are not
implied by isolation or implementation approval.

Distinguish merged, explicitly declined, pending, and retained work. Remove only owned, saved,
inactive resources after an explicit cleanup decision. Retain dirty, running, blocked, unknown,
failed, pending, or parked work. Keep artifacts and ownership records after failed removal.

- **Herdr owner:** use `herdr worktree remove --workspace <id>` without `--force`, after verifying
  no active/unsaved work. Ending/posting a PR review never auto-removes its workspace.
- **Worktrunk owner:** from outside the child checkout, use
  `wt -C <parent> remove <child-branch> --no-delete-branch --foreground --no-hooks --format json`.
  Keep the branch unless separate deletion is authorized. A declined checkout retains its branch.
- **External/unknown owner:** do not remove or prune it; report exact path and uncertainty.

Never infer saved/inactive state from an idle CLI alone. Never use force/clobber or process reaping
as routine cleanup. Branch deletion must independently prove integration into the parent and remain
non-forcing; a failed deletion preserves the branch.

## Chezmoi repositories

`chezmoi apply` reads the configured source, not an arbitrary worktree. Commit only scoped changes
when authorized, integrate into the main source only when authorized, and inspect target-limited
`chezmoi diff`. Apply only after explicit user permission. Preserve unrelated source changes.
Never claim a worktree change was applied without actual integration/apply evidence.

## Completion record

Report absolute path, branch/detached HEAD, committed base SHA, owner, workspace/pane IDs if any,
setup and verification evidence/not-run reasons, integration, liveness, and cleanup/retention state.
