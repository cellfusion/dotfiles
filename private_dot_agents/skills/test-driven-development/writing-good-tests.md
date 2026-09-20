# Writing Good Tests

**When to read**: When writing or modifying tests, adding mocks, or introducing test cleanup/helpers.

## Overview

Tests exist to catch specific regressions and breakages. Everything written here derives from two core principles:

```
1. Every test can name the breakage it catches
2. Every test runs real code
```

Disciplined TDD naturally produces both. A test written first that fails against real code has already proven its ability to fail. Mocks are introduced only when an actual dependency is demonstrated to be slow or external.

## Principle 1: Name the Breakage to Catch

Answer before writing the test body: **Which implementation change should cause this test to fail? And is that change a bug, or an intentional decision?**

Tests gain their reason for existence by catching incorrect branching, missed side effects, invalid arguments, edge cases, and broken contracts.

**Derive expectations independently.** Use literals and hand-verified fixtures. Table-driven tests with literal `want` fields represent the gold standard. Expectations computed by the code under test (or its helpers) will pass regardless of what the code actually does.

```typescript
// ❌ Mirror assertion: same builder computes both sides. Always true
const expected = buildSearchQuery({ tag: 'urgent' });
expect(buildSearchQuery({ tag: 'urgent' })).toBe(expected);

// ✅ Hand-derived literal
expect(buildSearchQuery({ tag: 'urgent' })).toBe('tag:"urgent"');
```

**Do not write change detectors.** Tests that fail only on intentional decisions (constant values, exact message phrasing, private data structures) fire on every design iteration while sleeping through actual bugs. Test the **behavior** that depends on the decision. Instead of `expect(MAX_RETRIES).toBe(5)`, verify that "a failing call is retried 5 times, and a 6th retry does not occur."

**Assert on behavior, not source text.** Asserting that a script, skill, or configuration contains specific lines only proves that the source code is what it is. Run scripts against controlled inputs and assert on output, side effects, and exit codes. Test agent instruction documents via the behavior of the agents that read them. Do not write tests that inspect human prose.

**Test your code, not the framework.** Test the contracts your code establishes at its boundaries: registered routes, issued queries, generated payloads. Upstream mechanics are tested by their own maintainers (e.g., asserting that a router invokes a registered handler tests the framework, not your application). Only when genuinely surprised by upstream behavior should you write a single narrow characterization test naming that assumption.

The same boundaries apply internally within your own code. Constructors, getters, constants, and pass-through forwarding deserve tests only when validation, normalization, defaults, derivation, enforcement, or side effects are present. Otherwise, assert the observable results from the first consumer that depends on them.

### Gate Function

```
Before writing the test body:
  Name the implementation change that should make this test fail.

  Cannot name one        -> Redesign around observable behavior
  "The source changed"   -> Execute the artifact and assert its effect
  Intentional decisions  -> Change detector. Test the behavior depending on the decision

  Verify expectations are derived without using code under test.
  If reusing code logic or helpers:
    Replace with literals or hand-verified fixtures
```

## Principle 2: Run the Real Thing

**Do not assert on mocks.** Assertions on mocks pass if the mock is present and fail if absent, saying nothing about the actual component. Assert on the real component's behavior. If you want to verify the mock itself, either unmock it or remove the assertion.

```typescript
// ✅ Real behavior
expect(screen.getByRole('navigation')).toBeInTheDocument();

// ❌ Verifying mock presence
expect(screen.getByTestId('sidebar-mock')).toBeInTheDocument();
```

**Mock at the right layer.** Identify all side effects of real methods before replacing them. Mock slow or external operations, leaving dependencies the test relies on intact. When uncertain, run tests against the real implementation first to observe what actually needs to happen.

```typescript
// ❌ Mock swallows config writes needed by duplicate detection
vi.mock('ToolCatalog', () => ({
  discoverAndCacheTools: vi.fn().mockResolvedValue(undefined)
}));

// ✅ Mock only the slow server launch; keep config writes real
vi.mock('MCPServerManager');
```

**Make test doubles specific.** Assert arguments, call counts, and ordering if they are part of the contract. Fakes that accept anything verify nothing. Separate fixtures or spies for each branch (success, error, invalid) so incorrect branches cannot satisfy expectations.

**Mirror real data completely.** Mocks must reflect full real-world structures (all documented fields), not just the fields the test happens to read. Partial mocks break silently when downstream code reads omitted fields. Tests pass, but integration fails.

**Implementation classes own only implementation methods.** Place cleanup needed solely by tests in test utilities, not in `destroy()` on implementation classes. Ask: "Is this method called only from tests?" "Does this class own the resource lifecycle?" If the answer is no, move it to test utilities.

**Prefer real objects over complex mocks.** When mock setup grows larger than test logic, when real methods are missing from mocks, or when tweaking mocks breaks unrelated tests, switch to integration tests using real implementations.

### Gate Function

```
Before adding mocks or test helpers:
  Enumerate side effects of the real method. Keep what tests depend on real,
  and mock the slow or external layer underneath.

  Mock responses must completely mirror real structures.

  Methods called only by tests belong in test utilities.

  Are you trying to assert on the mock itself?
    Unmock it or remove the assertion.
```

## Deliver Tests with Implementation

The TDD cycle (failing test -> minimal implementation -> refactor) defines "done." Deliver only the tests required for that behavior. Obvious code and human-facing prose do not need tests. Tests written solely to satisfy a procedural quota generate permanent maintenance debt.

## Mutation Check

Before finishing, mentally mutate the implementation code. For every realistic mutation, at least one test should fail:

- Wrong constants or arguments
- Incorrect branch handlers
- Dropped state changes or side effects
- Returning empty or default values
- Dropped validation for zero, empty, nil, unauthorized, or invalid input

Mutations caught by nothing indicate unverified behavior or tautological tests.

## Quick Reference

| When doing this | Do this |
|---|---|
| Writing tests | Name the breakage to catch: bugs, not design decisions |
| Creating expectations | Derive by hand; never compute with code under test |
| Testing scripts or docs | Execute them; do not grep source text |
| Tempted to test dependencies | Test contracts at your own boundaries |
| Tempted to assert on mocks | Test real behavior or unmock |
| Mocking a method | Identify side effects; mock at the slow/external layer |
| Crafting mock responses | Mirror real structures completely |
| Cleanup needed only by tests | Place in test utilities |
| Mock setup explodes | Switch to integration tests using real objects |
| Finishing test files | Run a mental mutation check |

## Red Flags

- Setup and assertion share the same object, guaranteeing equality
- Test can fail only via panic, crash, or missing selector
- Fails on intentional changes, but sleeps through accidental breakages
- Expectations hidden behind loops, builders, or helpers
- Grepping source text, or asserting that deleted symbols remain deleted
- Test remains meaningful even if only the framework remains
- Exists solely for code coverage, checking neither side effects nor results
- Verifying `*-mock` test IDs, or fails when removing a mock
- Methods called exclusively from test files
- Mock setup accounts for more than half the test, or mock necessity cannot be explained
- "Just in case" mocks
