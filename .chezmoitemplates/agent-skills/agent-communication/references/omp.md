# OMP Internal Communication

Confirm the tools actually exposed by the current OMP session. This reference describes the
`task` / `write` / `read` surface when available, not an API promised to every host.

## Dispatch and follow-up

Use `task` for justified bounded children. Provide goal, exact files, shared contracts, acceptance,
verification owner and stop conditions. Internal children do not inherit the parent's conversation
or permission to commit/push/apply. Follow host role and delegation rules; do not create a child
for a trivial question or to simulate another repository's workspace.

Record the actual returned child ID/handle. With the URI surface:

- `write` to `agent://<actual-id>` sends a follow-up to that child;
- `read` from `agent://<actual-id>` reads status/progress/result;
- completion/results arrive automatically. Use the host's wait mechanism only when blocked with
  no useful work remaining; do not poll repeatedly or wait for work you did not start.

Use the same `request_id` for a bounded assignment and `in_reply_to` for clarifications. Check that
a supplemental message was reflected in the result, not merely that the write succeeded. Completed
children may not accept further work: inspect the actual API/state instead of inventing resume.

## Eval alternative

Only if this host exposes the Eval agent API, read `xd://eval/agents` first. Its returned handle
supports `.send(message)`, `.output()` and `.wait(timeout)`. Keep one dispatch/message surface per
assignment; do not create another child because a different API looks more convenient. This is not
a shell command. Do not execute `agent://` or `task` as binaries.

## Boundaries

`agent://` addresses runtime-owned children, not every OMP conversation on the machine. Another
Herdr pane is not necessarily a child. Use the Herdr route for another repository's independent
owner. `local://` is host-local; for a separate session share a permitted real filesystem path.

Do not assume Claude's `SendMessage`, Codex's child tools, or an OMP resume API exist merely from
a generic runtime table. Read the actual tool contracts. If no internal messaging surface exists,
state that limitation; do not silently start a second CLI for same-repository delegation.
