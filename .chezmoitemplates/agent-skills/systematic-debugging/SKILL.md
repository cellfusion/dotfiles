---
name: systematic-debugging
description: >-
  Investigate a bug, test failure, build failure, performance issue, or unexpected behavior with
  evidence proportionate to the uncertainty. Implement a supported safe correction without making
  exhaustive reproduction or proof an unnecessary prerequisite.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Systematic Debugging

Establish what failed and use the available evidence to identify a supported correction. Investigate
unknowns that affect the implementation or its safety; do not require an exhaustive proof when a
safe, testable correction can proceed. A symptom-level patch that merely hides the failure is not a
valid completion.

## When to use this skill

Use it for test failures, production bugs, unexpected behavior, build or integration failures,
performance regressions, and flaky or environment-dependent failures. Use the full process for
high-risk incidents; use the compact process below for a deterministic, low-risk failure.

## Phase 1: establish evidence

Before changing code, use the evidence already available:

1. Read the relevant error, warning, stack trace, path, or report. Treat the user's observation as
   reported evidence; do not rerun a known failure merely to confirm it.
2. If an unknown affects the fix or its safety, choose the smallest safe observation or reproduction
   that can resolve it. Do not repeat destructive operations.
3. Record frequency, inputs, environment, and last known good revision when available and relevant.
4. Inspect only the relevant changes, dependencies, configuration, and boundaries.
5. Trace the failure far enough to support a correction and its verification.

When the approach is settled and remaining uncertainty does not prevent a safe implementation,
proceed with the correction. Record assumptions and verify the changed path afterward; do not claim
an unproven root cause. Required safety and approval boundaries still apply.

Use redacted diagnostics. Never print tokens, passwords, private keys, full environment values,
request bodies containing secrets, or unrestricted identity/keychain output. Record only presence,
counts, identifiers safe for the project, and the command/exit code.

For a multi-layer failure, capture one bounded run:

```text
boundary: input -> output -> relevant state
boundary: next layer input -> output -> relevant state
```

Stop investigating when the available evidence supports a safe, testable correction.

## Phase 2: compare a working pattern

When useful, compare a working example in the repository or supported version. Inspect differences
that could affect the failure or correction; do not turn an unrelated comparison into a gate.

## Phase 3: state one hypothesis

Write one falsifiable hypothesis:

```text
Because <evidence>, <component> is the first incorrect producer of <state>.
The smallest observation that can disprove this is <test/command>.
```

When a hypothesis needs testing, choose the smallest safe observation or controlled change that can
distinguish it. Preserve evidence from failed hypotheses. Do not accumulate speculative patches or
repeat experiments that cannot change the implementation decision.

## Phase 4: implement and prove the fix

When the available evidence supports a safe correction:

1. Create the smallest regression test or reproducible check before the fix when practical.
2. Make one focused correction; preserve existing user changes.
3. Run the regression check and relevant broader checks, reusing applicable evidence from this task.
4. Exercise the changed path and, when safe and practical, confirm the original symptom is gone.
5. Check for collateral regressions and cleanup unrelated diagnostic changes.
6. Record commands, exit codes, and evidence before claiming success.

Use `test-driven-development` for a behavior change with a usable test harness. For configuration,
documentation, generated files, or environments without a meaningful unit-test boundary, use the
strongest available static, integration, or reproducibility check instead and record why TDD was not
applicable.

## Flaky or environment-dependent failures

If the failure cannot be reproduced, preserve the available report and relevant observations. Do
not infer that the defect is absent from one successful attempt. Continue with a safe, testable
correction when the remaining uncertainty permits it; otherwise identify the concrete missing
evidence or safety decision. Distinguish `confirmed_root_cause`, `likely_root_cause`, and
`not_reproduced`.

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

1. use the reported error or capture it if a new observation is necessary
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
confirmed or likely root cause, or unknown
changed files
verification commands and exit codes
remaining uncertainty
```

Do not overwrite a previous investigation. Link follow-up attempts to the same incident ID.

## Stop conditions

Stop and ask when a material decision cannot be resolved from available evidence, for example:

- the expected behavior is unclear and a safe assumption would change the outcome
- the proposed fix expands scope or permissions
- diagnostics would expose secrets
- unresolved uncertainty prevents a safe, testable correction
- a redesign or destructive operation is required

Never claim a bug is fixed from a code change alone.
