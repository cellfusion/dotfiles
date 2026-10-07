## Delegate through a worktree

Use this route only when the approval gate explicitly selects a visible independent Herdr handoff.
Ordinary bounded delegation stays inside OMP; write isolation alone uses hidden Worktrunk without a
pane. Keep the parent pane open. `HERDR_ENV=1` was verified by the approval gate.

### 1. Re-read and scope the artifact

The on-disk artifact is canonical after any preview edits. Re-read its absolute path. Record goal,
allowed files, acceptance, verification owner, and constraints. Do not turn approval of a plan into
permission to commit, push, apply, install, or operate externally.

Read `using-git-worktrees` and `herdr`, then the current CLI help. Reuse an existing approved task
workspace if one exists; do not create a duplicate. Record known ownership, cwd, branch, workspace,
and pane. Unknown ownership or creation state requires inspection, not replacement.

### 2. Choose the branch and base

Use a unique safe branch such as `feat/<feature-name>`. Resolve the specified base to a commit SHA;
new main work defaults to the actual repository default branch, not guessed `main` or `master`.
A child continuing committed parent work uses its explicitly recorded parent base instead.

Check branch collision and prerequisites before creation. If required work is uncommitted, obtain a
user-scoped commit/transfer decision; never auto-copy the dirty tree or secret local files. A branch
collision stops creation and returns to the gate without modifying the existing branch.

### 3. Create one Herdr workspace

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" --branch "$NEW_BRANCH" \
  --base "$BASE_SHA" --label "$FEATURE_LABEL" --no-focus)
ws=$(printf '%s' "$out" | jq -er '.result.workspace.workspace_id')
pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id')
path=$(printf '%s' "$out" | jq -er '.result.worktree.path')
```

Use returned values, never predicted paths/IDs. Validate the checkout and base. Record owner
`herdr`, branch, base SHA, absolute path, workspace/root pane, integration `pending`, and liveness.
Incomplete JSON or failure after creation preserves all known IDs/paths and artifacts. Do not retry
creation, fallback to another owner/backend, or automatically remove a partially created workspace.

### 4. Start OMP in the root pane

The new root pane must be at its shell prompt. Use a unique name matching
`[a-z][a-z0-9_-]{0,31}` and a fresh private run-specific OMP session directory outside the repo:

```bash
herdr agent start "$AGENT_NAME" --kind omp --pane "$pane" -- \
  --cwd "$path" --session-dir "$SESSION_DIR"
```

Keep existing models and permissions. Do not create another agent pane or re-create the worktree.
Read OMP's current help before passing arguments. Readiness means ready for input, not task success.

### 5. Submit a bounded initial request

```bash
herdr agent prompt "$AGENT_NAME" "$BOUNDED_REQUEST" --wait --until working --timeout 120000
```

The request names only the absolute trusted plan/artifact path, task scope, actual cwd/branch/base,
verification owner, and constraints. Explicitly state that this environment already exists and must
not be re-created. Select `executing-plans` for a sequential plan or `multi-agent-development` for
independent slices; do not invent an “implement” recipe or force a multi-agent run. Do not depend
on slash-command interpretation. Never paste conversation history, credentials, or raw review logs.

A timeout, blocked/unknown state, or unconfirmed receipt is unresolved. Inspect the same agent,
pane, and artifact directory before any resume; never submit again or launch another CLI blindly.

### 6. Handoff record

Report exact workspace/root pane IDs, absolute checkout and artifact/session paths, branch, base,
owner, agent name, and observed readiness/submission status. Keep the parent available. Independent
work remains in the owned environment for inspection; ending a prompt is not permission to delete
it. Cleanup follows the ownership skill only after explicit saved/inactive/integration decisions.
