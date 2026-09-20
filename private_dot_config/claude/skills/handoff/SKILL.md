---
name: handoff
description: >-
  Procedure for spawning a clean successor Claude session in a new herdr pane when context
  pressure increases, passing a handoff document to continue work seamlessly.
  Use when context consumption exceeds ~60%, or when auto-compact / context limit warnings appear.
  Only valid when HERDR_ENV=1.
---

# Session Handoff

When context pressure mounts, hand over the baton before quality degrades by **launching a clean successor session in a new herdr pane, passing a handoff document**. The successor session continues subsequent tasks, and the current session terminates.

## Prerequisites and Initiation Criteria

- **Prerequisite**: Only active under herdr management (`HERDR_ENV=1`). If unset, rely on standard auto-compact and do not run this procedure. Never start herdr in environments where `HERDR_ENV` is not `1`, including Paseo.
- **Rule of thumb: when context usage is judged to exceed approximately 60%**. Since Claude cannot obtain exact token usage numbers, this is a heuristic self-assessment. **If auto-compact or context limit warnings appear, it is definitely the time to hand off immediately**.
- Even under pressure, **never hand off in the middle of an atomic work step**. If editing, complete up to a clean boundary or document uncommitted modifications explicitly in the handoff document before proceeding.

## Procedure

1. **Write the handoff document to disk** (do not pass it via argv). Save to `~/.config/claude/handoffs/` (run `mkdir -p` if not present), named `handoff-$(date +%Y%m%d-%H%M%S).md`. Pass the absolute path in step 3. It must be **self-contained** — the successor has no memory of this conversation and relies solely on CLAUDE.md, memory files, and this handoff document. Minimum contents:
   - Task objective / goal
   - Completed work
   - Next steps (ordered)
   - Relevant file paths and critical functions (`file_path:line`)
   - Decisions and rationale / rejected alternatives
   - Pitfalls / warnings
   - Git state (branch, uncommitted changes / stash)
   - Links to relevant memories (`[[name]]`)
   - **Because execution continues unattended with skip-permissions, explicitly label destructive/irreversible actions as "Requires user confirmation"** to prevent unintended actions.

2. **Create a new pane next to your own pane** (based on `$HERDR_PANE_ID`, same cwd). Do not use `--current` (which targets the user's focused pane and opens in a different workspace):

   ```bash
   herdr pane split "$HERDR_PANE_ID" --direction down --cwd "$PWD" --no-focus
   # Let the returned pane_id be <new_pane>
   ```

3. **Launch the successor session** (`CLAUDE_CONFIG_DIR` is resolved from `HERDR_SESSION` via zshrc, preserving it in a new pane within the same session. Explicitly provide the skip flag for unattended continuation):

   ```bash
   herdr pane run <new_pane> "claude --dangerously-skip-permissions 'Read <absolute path to handoff document> first, take over the tasks documented there, and proceed'"
   ```

4. **Verify the successor has started** before closing the current pane (never close if launch failed, preventing data loss):

   ```bash
   herdr pane wait-output <new_pane> --match "<claude prompt marker>" --timeout 60000
   # or herdr agent wait <new_pane> --until idle --timeout 60000
   ```

5. If verification succeeds, **terminate the current session** (close your own pane, exiting the current claude process):

   ```bash
   herdr pane close "$HERDR_PANE_ID"
   ```

## Guardrails

- **Do not close current pane until successor launch is confirmed**. If unconfirmed, keep open and report to user.
- **Avoid immediate re-handoff right after launch**. Successor must not immediately hand off again; complete at least one concrete work step before re-evaluating context pressure (chaining is intentional, but looping without progress must be prevented).
- Successor inherits CLAUDE.md, so if context fills up again, it will hand off in the same manner (intentional chaining).
