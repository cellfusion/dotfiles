---
name: test-driven-development
description: >-
  Use test-first development for behavior changes when a meaningful test boundary exists. Confirm a
  failing regression, implement the smallest correction, and verify the complete relevant suite.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Test-Driven Development

Test-first development is a way to prove intended behavior, not a ritual that fits every artifact.
Classify the change before choosing the loop.

## Applicability

Use the full red-green-refactor loop for:

- new behavior and public APIs
- bug fixes with a reproducible behavior
- business logic, data conversion, parsers, and error handling
- refactors with observable behavior that can regress

Use an appropriate alternative for:

- declarative configuration or dotfiles
- documentation and comments
- generated files
- dependency or build metadata with no executable behavior
- projects with no test harness or no meaningful isolated test boundary

For alternatives, define the expected invariant and use static validation, schema validation,
rendering checks, a safe integration check, or a manual verification record. Do not invent a fake
unit test merely to satisfy the label TDD. Record why test-first was not applicable.

## Core contract

When TDD applies:

```text
RED: write a focused test that expresses desired behavior
VERIFY RED: run it and confirm it fails for the intended reason
GREEN: implement the smallest change that passes it
VERIFY GREEN: run the focused and relevant broader tests
REFACTOR: improve structure without changing behavior
VERIFY: keep the suite green
```

Do not write production behavior first and retrofit a test that passes immediately. If that happens,
remove the implementation or reset the attempt and restart from the test. Do not preserve speculative
code as a reference implementation.

## RED: write the smallest useful test

A good test:

- names one behavior
- uses the real API and code path where practical
- asserts the observable result, error, or side effect
- covers the regression boundary
- avoids mocks unless the dependency cannot be exercised safely

Example:

```typescript
test('rejects an empty email address', async () => {
  const result = await submitForm({ email: '' });
  expect(result.error).toBe('Email required');
});
```

Before writing it, identify the behavior that should make the test fail. Keep test-only helpers in
test utilities, not production code.

## VERIFY RED

Run the smallest repository-supported test command. Confirm:

- the test actually ran
- it failed rather than crashing due to setup or a typo
- the failure message matches the missing behavior
- the test would have caught the original defect

If it passes, it is testing existing behavior or the wrong path. If setup fails, fix the test setup
or choose a valid boundary before continuing.

## GREEN: smallest implementation

Implement only what the failing test requires. Do not add unrelated abstractions, options, refactors,
optimizations, or features. Keep one behavioral variable per attempt.

## VERIFY GREEN

Run:

1. the focused test
2. the relevant package/module suite
3. the repository's required checks when the change warrants them

Record exact commands, exit codes, and failure counts. A passing focused test is not proof that
unrelated behavior remains safe.

## REFACTOR

Refactor only after green:

- remove duplication
- improve names
- extract a helper
- simplify setup

Do not change behavior during refactor. Re-run the same checks after each meaningful refactor.

## Configuration and documentation path

For non-behavioral changes, use this substitute loop:

```text
DEFINE: state the invariant or rendered output that must hold
CHANGE: make the smallest edit
CHECK: render, parse, validate, diff, or inspect the result
REGRESS: run repository checks that cover the artifact
RECORD: save the command and result
```

Examples include rendering a chezmoi template, validating JSON/YAML, checking shell syntax, testing
that a generated file is distributed, or running `git diff --check`. Never claim “tests pass” when
only a configuration check was performed.

## Multiple changes

For several independent behaviors:

1. write and verify one red test
2. implement and verify one green behavior
3. record the result
4. start the next red test

Keep changes isolated so a failure has one clear cause.

## Completion checklist

- [ ] change classified as behavior, configuration, documentation, generated, or metadata
- [ ] appropriate test or substitute check written first
- [ ] red evidence observed when TDD applied
- [ ] smallest implementation made
- [ ] focused and relevant broader checks passed
- [ ] edge cases and error paths considered
- [ ] commands and exit codes recorded
- [ ] no unrelated changes remain

Do not bypass a required item silently. If the item is not applicable, record the reason and the
alternative evidence.
