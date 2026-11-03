---
name: handoff
description: >-
  Prepare a self-contained handoff record when a session needs to be continued elsewhere.
  Prefer normal context compaction; do not automatically launch or terminate sessions.
---

# Session Handoff

Prefer the current session's normal context-compaction and continuation mechanisms. When a handoff
record is needed, complete the current atomic step or record its incomplete state before writing.
This procedure applies in herdr-core, legacy Herdr, and ordinary shells.

## Prepare the record

Write a self-contained document to `~/.config/claude/handoffs/`, named
`handoff-<date-and-time>.md`. Include:

- Task objective, completed work, and ordered next steps.
- Relevant paths and important functions; decisions, rejected alternatives, and unresolved questions.
- Worktree path, branch, uncommitted changes and integration state, as actually observed.
- Active or retained resources, their ownership and addresses when verified, and outstanding requests.
- Checks run and their results; checks not run; actions requiring user approval.

Do not include credentials, authentication material, or unrelated conversation history. Give the
user the absolute path. Writing a record does not authorize a successor to commit, push, apply,
install, delete resources, or bypass a permission prompt.

## Continuing elsewhere

Do not automatically start a successor or terminate the current session. If the user requests a
separate session, use the selected host's skill and version-matched manual; pass the record path and
the explicitly authorized scope. Preserve the existing permission settings.

For herdr-core, read `herdr-core` and `hc --skill`, verify terminal and checkout identity, and keep
terminal addresses separate from app pane IDs. Children normally end when their parent ends;
`--outlive-parent` changes that lifetime and needs an explicit reason. Launch acceptance, initial
message delivery, readiness, and successful continuation are separate facts. Inspect the same
terminal on failure or uncertain delivery; do not blindly retry or close the current session.

For legacy Herdr, follow the legacy host skill rather than treating `HERDR_PANE_ID` as a core
address. An ordinary shell must not start Herdr merely to create a handoff. Only change the visible
app layout when the user requests it, and never stop or restart the user's core.
