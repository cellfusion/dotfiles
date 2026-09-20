---
name: receiving-code-review
description: >-
  Evaluate code-review feedback before implementing it. Verify every actionable item against the
  codebase, record the decision, and choose a direct or delegated fix route proportional to scope.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Receive and Act on Code Review

Code review feedback is technical input, not an instruction to agree or implement blindly. Preserve
the reviewer context, verify the claim against the repository, and make the decision traceable.

## 1. Normalize the feedback

Read all feedback before responding. Assign stable IDs when the reviewer did not provide them:

```text
F-001, F-002, ...
```

For each item, capture:

- reviewer text and source (human, PR review, child reviewer, CI)
- affected path and line, if any
- claimed behavior or risk
- requested outcome
- priority and confidence, if supplied

Do not copy secrets or unrelated conversation into the record.

## 2. Verify before deciding

For each item, restate the technical claim in one sentence and inspect the relevant code, tests,
callers, configuration, and supported versions. Confirm:

1. Is the claim true in this repository and revision?
2. Does the proposed change preserve existing behavior and compatibility?
3. Is the current implementation intentional or required by a documented constraint?
4. Is the affected code actually used? Check callers before accepting broad refactors.
5. Can the claim be verified with a focused test, static check, or reproducible observation?

If verification is incomplete, mark the item `needs_context` rather than treating it as accepted.
Do not implement an unclear item while waiting for clarification on a related item.

## 3. Decide explicitly

Use one decision per finding:

- `accept`: technically valid and in scope
- `reject`: technically incorrect, unsupported, or incompatible; preserve the evidence
- `clarify`: the requested behavior or scope is ambiguous
- `defer`: valid but intentionally outside the current scope; record the reason and follow-up
- `duplicate`: already covered by another finding ID
- `fixed`: implemented and independently verified

A useful decision record is:

```json
{
  "id": "F-001",
  "decision": "accept",
  "reason": "The caller can pass an empty value and the changed branch does not reject it.",
  "evidence": ["src/input.ts:42", "tests/input.test.ts:18"],
  "scope": "current-task",
  "nextAction": "add regression test and fix validation"
}
```

Keep these records in the external review artifact directory, not in the repository working tree.
When the parent has a project-wide audit log, append a sanitized decision event there instead of
creating a second incompatible log.

## 4. Choose the implementation route

Use the smallest safe route:

- direct parent implementation for a small, local, well-understood correction
- one isolated implementer for a bounded multi-file correction
- MAD fix/re-review for parallel, architectural, or high-risk work
- user decision when the fix changes the public contract, scope, or architecture

Do not make child delegation mandatory. Do not let a reviewer choose provider, model, permissions,
or worktree ownership. Pass only the finding, fixed review package, allowed files, requirements, and
verification commands.

For multiple accepted findings, order work as:

1. blockers and security/data-integrity issues
2. correctness and compatibility issues
3. focused tests and error handling
4. minor cleanup

Keep unrelated cleanup out of the fix scope.

## 5. Verify each fix

For each accepted item:

1. Create or identify the regression test before the fix when the behavior is testable.
2. Implement only the allowed change.
3. Run the focused test or static check and record the exit code.
4. Re-run the relevant broader checks.
5. Create a fresh diff/review package and verify that the finding is resolved.
6. Mark the item `fixed` only after independent evidence exists.

If the reviewer was wrong, respond with concise technical evidence. If the initial rejection was
wrong, record the correction and proceed without a performative apology.

## 6. GitHub thread replies

Reply to an inline GitHub review comment in its thread, not as a top-level PR comment:

```bash
gh api --method POST \
  "repos/<owner>/<repo>/pulls/<pr>/comments/<comment-id>/replies" \
  -f body="<technical response>"
```

Only post after the user or the surrounding workflow authorizes external writes. Keep the response
factual: state the verification, decision, and commit or artifact containing the fix.

## Stop conditions

Stop and ask for a decision when:

- any item is unclear and affects implementation scope
- feedback conflicts with an explicit user or architecture decision
- the proposed fix expands the public contract or permissions
- verification cannot distinguish between multiple root causes
- the fix would require unrelated files or destructive operations

Never claim that all feedback was addressed until every finding ID has a decision and, for `fixed`,
fresh verification evidence.
