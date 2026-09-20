## Delegating to Worktree

Execute only when "Approve & Delegate via worktree" is selected at the approval gate. Create a worktree as a new workspace and hand off implementation to a Claude session launched in that pane. The delegating session waits without closing its pane.

`$HERDR_ENV` being `1` is already verified by the approval gate checks.

### 1. Re-read Plan

Previews are opened in editable mode. Manual edits exist only in the file. Content re-read from disk is authoritative.

### 2. Determine Branch Name

Strip the date from the plan file name to form `feat/<feature-name>`. For instance, `~/docs/<owner>/<repo>/plans/2026-08-14-worktree-handoff.md` becomes `feat/worktree-handoff`.

```bash
git rev-parse --verify "feat/<feature-name>" 2>/dev/null
```

If exit status is 0, a branch with that name already exists. Report the conflict without creating anything and return to the approval gate.

### 3. Create Worktree as Workspace, Reading ID and Path from Response

Execute in a single bash invocation. Keep as a single contiguous block. Splitting across invocations empties `$out` and leaves subsequent values empty.

```bash
out=$(herdr worktree create \
  --workspace "$HERDR_WORKSPACE_ID" \
  --branch "feat/<feature-name>" \
  --base HEAD \
  --label "<feature-name>" \
  --no-focus)

ws=$(printf '%s' "$out" | jq -r '.result.workspace.workspace_id')
pane=$(printf '%s' "$out" | jq -r '.result.root_pane.pane_id')
path=$(printf '%s' "$out" | jq -r '.result.worktree.path')
```

- **Always pass `--workspace`.** If omitted, the user's currently focused workspace is used, possibly creating it elsewhere.
- **Pass `--no-focus`.** The delegating session continues reporting afterward; do not hijack focus.
- **Do not pass `--path`.** herdr creates it under `~/.herdr/worktrees/<repo>/<branch>`. Since this is outside the repository, checking `.gitignore` is unnecessary.

If any of the 3 values is empty or `null`, delegation fails. If `ws` is obtained, clean up with `herdr worktree remove --workspace "$ws" --force`. If `ws` could not be obtained, report the failure and return to the approval gate.

Subsequent steps (5, 6, cleanup on failure) assume `$out` / `$ws` / `$pane` / `$path` are not preserved across subsequent bash tool calls. Populate acquired values as literals.

### 5. Launch Claude in that Pane

```bash
herdr agent start "<agent-name>" --kind claude --pane "$pane"
```

- Use `<agent-name>` directly from feature-name. Replace characters outside `[a-z][a-z0-9_-]{0,31}` with `-`, truncating if exceeding 32 characters.
- **Do not pass permission bypass flags.** When approval is required, execution pauses in that workspace for user review.

### 6. Send Initial Prompt

```bash
herdr agent prompt "<agent-name>" "<prompt>" --wait --timeout 120000
```

Include only the following 4 items in the prompt. Do not paste conversation history:

- The plan's **absolute path**. The destination lies outside the working tree and resolves identically from any checkout.
- Instruct to implement this plan using the `multi-agent-development` implement recipe.
- State that the worktree is already prepared, so do not create a new one.
- Provide the branch name of this worktree.

**Timeouts are not failures.** `--wait` waits for the delegate to begin running MAD, so reaching `--timeout 120000` is expected. Do not delete the worktree on timeout; proceed to step 7.

### 7. Report and Stand By

Report workspace ID, absolute worktree path, branch name, and agent name. **Do not close your own pane.** The user can continue using this session for subsequent tasks.

### On Failure

**Cleanup applies only to failures during steps 2–4 (before `herdr agent start`).** Up to that point, only the delegating session is aware of the worktree and workspace, so deletion is safe: `herdr worktree remove --workspace "$ws" --force`. After cleanup, report and return to the approval gate.

**Do not delete the worktree if failure occurs at or after step 5 (`herdr agent start`).** The delegate Claude session may have already started, and force-deleting the worktree destroys active sessions. Report workspace ID and absolute worktree path stating: "Delegate agent launched, but receipt of initial prompt could not be confirmed," and return to approval gate.
