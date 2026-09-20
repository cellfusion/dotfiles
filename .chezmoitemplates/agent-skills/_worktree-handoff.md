## Delegate through a worktree

Use this section only when the approval gate explicitly selects worktree delegation. Create a new
workspace and start the delegated Claude session there. Keep the parent pane open.

`HERDR_ENV=1` was already verified by the approval gate.

### 1. Re-read the artifact

The preview editor may have allowed manual edits. Re-read the file from disk; on-disk content is
canonical.

### 2. Choose a branch

Remove the date from the plan filename and use `feat/<feature-name>`. For example,
`2026-08-14-worktree-handoff.md` becomes `feat/worktree-handoff`.

```bash
git rev-parse --verify "feat/<feature-name>" 2>/dev/null
```

If the branch exists, create nothing, report the collision, and return to the approval gate.

### 3. Create the Herdr workspace

Run this as one shell block and read every value from the response:

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --branch "feat/<feature-name>" \
  --base HEAD \
  --label "<feature-name>" \
  --no-focus)
ws=$(printf '%s' "$out" | jq -er '.result.workspace.workspace_id')
pane=$(printf '%s' "$out" | jq -er '.result.root_pane.pane_id')
path=$(printf '%s' "$out" | jq -er '.result.worktree.path')
```

Always pass `--workspace` and `--no-focus`; do not pass `--path`. If any value is empty or null,
remove the workspace only when `ws` is known. If it is unknown, report the orphan risk and return to
the gate. Record workspace ID, pane, path, branch, and ownership.

Values from this shell block are not available in later shell calls. Use the validated literal values
in subsequent commands; never predict a path or ID.

### 4. Start the delegated agent

```bash
herdr agent start "<safe-agent-name>" --kind claude --pane "$pane"
```

Sanitize the agent name to `[a-z][a-z0-9_-]{0,31}`. Do not add permission-bypass flags. The agent
must stop for approval when approval is required.

### 5. Send the initial prompt

```bash
herdr agent prompt "<safe-agent-name>" "<bounded prompt>" --wait --timeout 120000
```

Include only:

- the plan's absolute path
- instruction to implement it using the `multi-agent-development` implement recipe
- statement that the worktree already exists and must not be recreated
- the existing worktree branch name

Do not paste conversation history, credentials, or raw review output. A timeout is not proof of
failure; inspect agent state and artifacts before deciding.

### 6. Report and wait

Report workspace ID, absolute worktree path, branch, agent name, and current status. Do not close the
parent pane. The user may continue using it.

### Failure handling

Before `agent start`, cleanup is safe only for the worktree created by this run and only when its
workspace ID is known. After `agent start`, never force-remove the workspace because the delegated
session may still be running. Report that the agent may be active and that receipt of the initial
prompt is unconfirmed. Keep the workspace and return to the approval gate.
