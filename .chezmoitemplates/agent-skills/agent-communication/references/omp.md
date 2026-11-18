# OMP Communication Through HC

For justified OMP delegation, use `hc run` and the
[herdr-core communication contract](herdr-core.md). Read `herdr-core` and the installed
`hc --skill` first. This is guidance, not an override of higher-priority runtime policy:
if HC is unavailable or conflicts with that policy, report the blocker; do not silently use
OMP `task`, Eval agents, or another backend as a fallback.

Give each child a bounded request with a unique `request_id`, exact cwd and allowed files,
shared contracts, acceptance, verification owner, stop conditions and either the parent's verified
return address or an actual shared result path / `hc read` procedure when the parent is outside HC.
Do not pass credentials or unrelated history; do not authorize recursive agents, commit, push,
apply or install unless explicitly assigned.

Record the returned full terminal address and inspect `first_message.sent`. Expand the parent's
address before launch: the child's `$HC_TERMINAL_ID` names the child. Follow the live manual for
readiness, `hc send`, `hc read` and finite `hc wait`; do useful work rather than polling. A
timeout, blocked approval or ambiguous delivery is unresolved: inspect the same terminal, do not
force approval, resend blindly, launch a replacement or switch backend. A wait or idle state is
not completion; correlate the actual reply and `request_id` before adoption.

An HC terminal is neither a pane nor checkout ownership. For another repository select its
independently identified owner; for write isolation follow `using-git-worktrees`. Share permitted
absolute paths rather than host-local `local://` handles. Never infer identity from an example.
