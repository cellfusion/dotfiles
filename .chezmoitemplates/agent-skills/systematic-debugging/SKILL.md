---
name: systematic-debugging
description: >-
  Identify root cause before proposing a fix for a bug, test failure, build failure, performance issue,
  or unexpected behavior. Gather evidence, test one hypothesis at a time, and stop when the evidence
  no longer supports the current approach.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Systematic Debugging

Do not start with a fix. Start by establishing what failed, how to reproduce it, and where the
first incorrect state appears. A symptom-level patch without a causal explanation is not a valid
completion.

## When to use this skill

Use it for test failures, production bugs, unexpected behavior, build or integration failures,
performance regressions, and flaky or environment-dependent failures. Use the full process for
high-risk incidents; use the compact process below for a deterministic, low-risk failure.

## Phase 1: establish evidence

Before changing code:

1. Read the complete error, warning, stack trace, path, line, and error code.
2. Reproduce the failure with the smallest reliable command or scenario.
3. Record frequency, inputs, environment, and the last known good revision.
4. Inspect recent diff, dependency, configuration, and environment changes.
5. For multi-layer systems, observe each boundary without logging secrets.
6. Trace the invalid value backward to its first incorrect producer.

Use redacted diagnostics. Never print tokens, passwords, private keys, full environment values,
request bodies containing secrets, or unrestricted identity/keychain output. Record only presence,
counts, identifiers safe for the project, and the command/exit code.

For a multi-layer failure, capture one bounded run:

```text
boundary: input -> output -> relevant state
boundary: next layer input -> output -> relevant state
```

Stop when the evidence identifies the first layer that diverges from the expected contract.

## Phase 2: compare a working pattern

Find a working example in the same repository or supported version. Read the relevant reference
implementation completely enough to understand its preconditions. List every difference between the
working and failing paths; do not dismiss a difference without evidence. Include configuration,
permissions, dependency versions, timing, and data shape.

## Phase 3: state one hypothesis

Write one falsifiable hypothesis:

```text
Because <evidence>, <component> is the first incorrect producer of <state>.
The smallest observation that can disprove this is <test/command>.
```

Test only that hypothesis with the smallest read-only observation or one controlled change. Do not
apply several fixes at once. If it fails, preserve the evidence and return to Phase 1 with a new
hypothesis. Do not accumulate speculative patches.

## Phase 4: implement and prove the fix

After the root cause is supported:

1. Create the smallest regression test or reproducible check before the fix when practical.
2. Make one focused correction at the root cause.
3. Run the regression check and relevant broader checks.
4. Reproduce the original scenario and confirm the original symptom is gone.
5. Check for collateral regressions and cleanup unrelated diagnostic changes.
6. Record commands, exit codes, and evidence before claiming success.

Use `test-driven-development` for a behavior change with a usable test harness. For configuration,
documentation, generated files, or environments without a meaningful unit-test boundary, use the
strongest available static, integration, or reproducibility check instead and record why TDD was not
applicable.

## Flaky or environment-dependent failures

If the failure cannot be reproduced:

- record exact attempts, environment, timing, and available logs
- compare the failing and successful environments
- add safe observability or a deterministic reproduction harness
- do not claim the root cause is absent merely because one run passed
- distinguish `confirmed_root_cause`, `likely_root_cause`, and `not_reproduced`

When external services are involved, do not retry destructive operations. Use read-only inspection
or a disposable fixture.

## Escalation boundary

Do not use an arbitrary number of retries as proof of an architectural problem. Escalate when the
evidence shows that the current component boundary, contract, or architecture cannot satisfy the
requirement, or when repeated hypotheses fail without new information. At that point:

1. summarize confirmed facts and rejected hypotheses
2. state the smallest architectural choices
3. explain impact, migration, and rollback
4. ask the user before broad refactoring or redesign

A timeout, missing dependency, invalid schema, or known test failure is not automatically an
architecture issue; classify it and fix the deterministic cause first.

## Compact path for obvious failures

For a deterministic syntax error or a failure whose message identifies the exact changed line:

1. capture the fresh error
2. verify the referenced line and relevant recent diff
3. make one correction
4. rerun the exact failing command and a focused regression check
5. report evidence

Do not skip this process merely because the fix appears obvious.

## Debugging record

Keep a concise external record when the investigation spans multiple attempts:

```text
incidentId
repository/revision
environment summary without secrets
reproduction command and exit code
observations
hypotheses and outcomes
confirmed root cause
changed files
verification commands and exit codes
remaining uncertainty
```

Do not overwrite a previous investigation. Link follow-up attempts to the same incident ID.

## Stop conditions

Stop and ask when:

- the reproduction or expected behavior is unclear
- the proposed fix expands scope or permissions
- diagnostics would expose secrets
- verification cannot distinguish competing hypotheses
- the current approach has no new evidence
- a redesign or destructive operation is required

Never claim a bug is fixed from a code change alone.
