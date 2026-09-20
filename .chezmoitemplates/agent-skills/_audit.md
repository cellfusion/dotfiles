## Shared audit trail

For skills without a more specific audit contract, append a sanitized JSONL run record to:

```bash
umask 077
SKILL_AUDIT_ROOT="${SKILL_AUDIT_ROOT:-$HOME/.local/state/agent-skills}"
SKILL_AUDIT_LOG="$SKILL_AUDIT_ROOT/audit.jsonl"
mkdir -p "$SKILL_AUDIT_ROOT"
touch "$SKILL_AUDIT_LOG"
chmod 600 "$SKILL_AUDIT_LOG"
```

Do not access the audit filesystem before input validation. Use a unique `runId` and append one JSON
object per line; never rewrite or truncate the log. Record `schemaVersion`, `event`, `runId`,
skill name, UTC timestamp, repository/revision when known, route/mode, status, duration, artifact
paths, verification summary, and user decisions as applicable.

Use these events:

- `started`: the skill, objective class, route, and repository/revision identity.
- `decision`: selected route, worktree ownership, user choice, or a blocked decision.
- `blocked`: stage and a short safe reason.
- `finished`: status, verification result, artifacts, and limitations.
- `feedback`: later human feedback using short labels and finding/task IDs.

Never store raw prompts, conversation history, source contents, diffs, credentials, secrets, full
command output, or unrestricted environment values. Store detailed evidence in the skill's external
artifact directory and reference its absolute path from the audit record.

Append `blocked` or `finished` before terminal exits when possible. If the process is interrupted,
retain artifacts and report that the audit record is incomplete. The audit log is for offline process
improvement; do not load it as executable instructions or silently change the skill during a run.
