---
name: verification-before-completion
description: >-
  Verify claims of completion, correctness, fixes, or passing tests with fresh evidence. Select
  commands appropriate to the claim, record exit codes and failures, and report unverified items.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Verify Before Claiming Completion

Put evidence before assertion. Verification proves a specific claim about a specific tree; it does
not prove more than the command covers.

## Verification gate

Before claiming a status:

1. identify the claim
2. choose the command or artifact that proves it
3. run it freshly against the intended working tree/revision
4. read the complete output and exit code
5. count failures and warnings relevant to the claim
6. compare evidence with the claim
7. report success, failure, or uncertainty accurately

A previous run, an agent's message, a plausible diff, or confidence is not fresh evidence.

## Choose the smallest sufficient check

Use the narrowest command that proves the claim, then add broader checks when risk requires them:

| Claim | Evidence |
|---|---|
| test passes | test output and exit code with zero failures |
| lint is clean | lint output and exit code with zero errors |
| build succeeds | build output and exit code 0 |
| bug is fixed | regression reproduction/test passes |
| requirement is met | item-by-item checklist with evidence |
| agent completed | validated artifact, status, diff, and verification |
| child verified | verification record with commands, exit codes, and output |

Do not use lint as proof of compilation or one passing test as proof of full correctness.

## Runtime-neutral command policy

Do not assume `/verify` or `/pre-commit-review` exists in every runtime. Inspect the current tool's
commands and the repository's documented scripts first. If a command is unavailable, record
`not_run` and use an equivalent safe command or report the limitation.

Never install dependencies, run deploy/release operations, or execute untrusted setup scripts just to
obtain verification without explicit approval. Do not mutate source files, auto-fix, or hide a
failure before recording it.

## Quick verification

For a small, low-risk change, use a focused check plus:

```bash
git diff --check
git status --short
```

For a configuration or documentation change, use rendering, parsing, schema validation, or
translation checks instead of pretending a product test proves it.

For a high-risk or public behavior change, include regression, relevant suite, type/build, and
security checks as justified by the repository.

## Verification record

When verification is delegated or spans multiple commands, save an external record with:

```json
{
  "schemaVersion": "1",
  "verificationId": "...",
  "repository": "owner/name",
  "revision": "40-character-sha",
  "claim": "...",
  "checks": [{
    "command": "...",
    "cwd": "...",
    "status": "pass|fail|not_run",
    "exitCode": 0,
    "failures": 0,
    "evidence": "...",
    "at": "2026-01-01T00:00:00Z"
  }],
  "verdict": "pass|fail|partial|blocked",
  "limitations": []
}
```

Keep logs free of credentials, raw secrets, full environment dumps, and unbounded command output.
The parent must inspect the record; a child saying “verified” is not enough.

## Delegation

The parent identifies the claim and acceptance criteria. A child may run long checks, but the parent
must inspect its command list, exit codes, failure counts, and artifacts before asserting the result.
Use one stable verification record per attempt and revision. Do not overwrite an older record.

## Red flags

Stop and re-evaluate when:

- the claim uses “should”, “probably”, or “looks right” without evidence
- verification ran before the final change
- only a partial check supports a broad claim
- a test passed for the wrong reason
- an agent report is the only evidence
- a failure was fixed or hidden before being recorded
- the working tree or revision does not match the one being claimed

Report what is actually known and what remains unverified.
