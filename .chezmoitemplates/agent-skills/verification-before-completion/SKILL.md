---
name: verification-before-completion
description: >-
  Use right before claiming completion, fixes, or test passage, and before committing or creating PRs.
  Execute verification commands proving claims, confirm output, and only then assert results.
  Place evidence before assertion.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Verify Before Claiming Completion

## Overview

**Core**: Put evidence before assertion. Always.

**Breaking the letter of this rule breaks the spirit of this rule.**

## Iron Rule

```
Never claim completion without fresh evidence of verification
```

If you have not run a verification command within the current turn, you cannot claim it passes.

## Gate Function

```
Before asserting any status or expressing satisfaction:

1. Identify: What command proves this claim?
2. Execute: Run that command completely (freshly, unabbreviated)
3. Read: Read the full output, verify exit code, and count failures
4. Verify: Does the output substantiate the claim?
   - No: State the actual situation accompanied by evidence
   - Yes: Make the claim accompanied by the evidence
5. Only then assert the claim

Skipping any step constitutes falsification, not verification
```

## Who Executes Verification

Steps 2 (Execute) and 3 (Read) of the Gate Function may be performed by the parent directly or delegated to a child. Steps 1 (Identify), 4 (Verify), and 5 (Assert) are always performed by the parent.

- **Few verification commands with brief output** — Parent runs them directly. `/verify` is an example.
- **Lengthy verification or voluminous output** — Delegate to a child using MAD's `review` recipe, passing commands and requirements paths. The child records executed commands, exit codes, output, and rationale per requirement into a verification record, returning its absolute path.

Even when delegating to a child, the parent inspects exit codes and failure counts from the verification record. **A child's report that it "succeeded" is not evidence.** Without exit codes and command outputs in the record, verification did not occur.

## Common Pitfalls

| Claim | Required Evidence | Insufficient Evidence |
|---|---|---|
| Tests pass | Test command output: 0 failures | Prior run, "should pass" |
| Clean lint | Lint output: 0 errors | Partial check, extrapolation |
| Build passes | Build command: exit code 0 | Passing lint, "logs look good" |
| Bug fixed | Test reproducing original symptom: passes | "Should be fixed since code changed" |
| Regression test works | Confirmed red-green | Passed once |
| Agent completed | Changes visible in VCS diff | Agent's "success" message |
| Child verified | Verification record exit code & output | Child's claim that it verified |
| Requirements met | Line-by-line checklist verification | "Tests are green" |

In this project, `/verify` runs the full verification suite (build, typecheck, lint, test, debug audit). When uncertain what to run, use `/verify`.

## Red Flags — Stop

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("done", "works great", etc.)
- Attempting to commit, push, or open a PR without verifying
- Trusting agent success reports blindly
- Relying on partial verification
- Thinking "just this once"
- Fatigued and wanting to wrap up
- **Using phrasing implying success without running verification**

## Handling Rationalizations

| Rationalization | Reality |
|---|---|
| "Should work by now" | Run verification |
| "I'm confident" | Confidence is not evidence |
| "Just this once" | No exceptions |
| "Lint passed" | Linters are not compilers |
| "Agent said success" | Verify independently |
| "I'm tired" | Fatigue is not an excuse |
| "Partial check is enough" | Partial checks prove nothing |
| "Phrased differently, so rule doesn't apply" | Obey the spirit, not just the letter |

## Patterns

**Tests**

```
✅ [Run test command] [Verify 34/34 passed] "All tests pass"
❌ "This should pass now", "Looks correct"
```

**Regression Tests (TDD red-green)**

```
✅ Write -> run (pass) -> revert fix -> run (must fail) -> reapply fix -> run (pass)
❌ "Wrote regression test" (without verifying red-green)
```

**Build**

```
✅ [Run build] [Verify exit code 0] "Build succeeds"
❌ "Lint passed" (linting does not verify compilation)
```

**Requirements**

```
✅ Re-read plan -> build checklist -> verify item by item -> report gaps or completion
❌ "Tests pass, so phase is complete"
```

**Agent Delegation**

```
✅ Agent reports success -> inspect VCS diff -> verify changes -> report actual state
❌ Trusting agent report at face value
```

## When to Apply

**Always, prior to**:
- Any statement expressing success or completion
- Any expression of satisfaction
- Any affirmative statement about work status
- Commits, PR creation, task completion
- Advancing to the next task
- Delegating to an agent

**Scope of the rule**:
- Exact phrasing
- Paraphrases and synonyms
- Implied success
- Any communication suggesting completion or correctness
