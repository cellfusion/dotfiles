---
name: systematic-debugging
description: >-
  Use before proposing fixes when encountering bugs, test failures, or unexpected behaviors.
  Entry point for requests like "not working", "fails", or "crashing unexpectedly".
  Enforces identifying root causes before attempting fixes.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Systematic Debugging

## Overview

**Core**: Always find the root cause before attempting fixes. Treating symptoms is failure.

**Breaking the letter of this process breaks the spirit of debugging.**

## Iron Rule

```
Never attempt a fix before investigating the root cause
```

Do not propose fixes until Phase 1 is complete.

## When to Use

Use for all technical problems:

- Test failures
- Production bugs
- Unexpected behaviors
- Performance degradations
- Build failures
- Integration issues

**Especially critical when**:
- Under time pressure (urgency makes guessing tempting)
- Looks like a "one-line quick fix"
- Multiple fixes have already been attempted
- Previous fix failed
- The problem is not fully understood

**Never skip because**:
- It looks simple (simple bugs have root causes too)
- You're in a hurry (rushing guarantees rework)
- Pressured to fix immediately (systematic methods are faster than thrashing)

## Four Phases

Complete each phase before advancing to the next.

### Phase 1: Root Cause Investigation

**Before any fix attempts**:

1. **Read Error Messages Carefully**
   - Never skim errors or warnings
   - The solution is often explicitly stated
   - Read stack traces to the bottom
   - Note line numbers, file paths, and error codes

2. **Reproduce Consistently**
   - Can you trigger it reliably?
   - What are the exact reproduction steps?
   - Does it happen every time?
   - If not reproducible, collect data instead of guessing

3. **Check Recent Changes**
   - What changed to cause this?
   - Review `git diff`, recent commits
   - New dependencies, configuration changes
   - Environmental diffs

4. **Gather Evidence in Multi-Tier Systems**

   When a system spans multiple components (CI -> build -> signing, API -> service -> database), **add diagnostic instrumentation before proposing fixes**:

   ```
   For each component boundary:
     - Log inputs
     - Log outputs
     - Verify environment variable and config propagation
     - Check state at each layer

   Run once to collect evidence showing where execution breaks
   -> Analyze evidence to isolate the failing component
   -> Investigate that component
   ```

   Multi-tier example:
   ```bash
   # Layer 1: Workflow
   echo "=== secret visible in workflow ==="
   echo "IDENTITY: ${IDENTITY:+SET}${IDENTITY:-UNSET}"

   # Layer 2: Build script
   echo "=== env in build script ==="
   env | grep IDENTITY || echo "IDENTITY not in environment"

   # Layer 3: Signing script
   echo "=== keychain state ==="
   security list-keychains
   security find-identity -v
   ```

   This reveals **which layer dropped execution** (secret -> workflow ✓, workflow -> build ✗).

5. **Trace Data Flow Backward**

   If an error occurs deep in the call stack, consult [root-cause-tracing.md](root-cause-tracing.md):
   - Where was the invalid value born?
   - Who called this with the invalid value?
   - Trace up until reaching the source
   - Fix at the source, not the symptom

### Phase 2: Pattern Analysis

**Find patterns before fixing**:

1. **Find Working Examples** — Locate code in the same codebase behaving similarly and working.
2. **Compare with Reference Implementations** — Read reference implementations **completely**. Do not skim. Understand thoroughly before applying.
3. **Isolate Diffs** — List every difference between the working and broken cases. Never assume "this detail doesn't matter".
4. **Map Dependencies** — What else is needed? Which configurations/environments are required? What assumptions exist?

### Phase 3: Hypothesis and Verification

**Follow the scientific method**:

1. **Formulate a Single Hypothesis** — State clearly: "I believe X is the root cause because Y." Write it down. Avoid ambiguity.
2. **Test with Minimal Change** — Make the **smallest** modification to test the hypothesis. One variable at a time. Do not fix multiple things at once.
3. **Verify Before Proceeding** — Did it work? If yes -> Phase 4. If no -> formulate a **new hypothesis**. Do not pile on additional fixes.
4. **Admit When Unsure** — Do not pretend to know. Ask for help. Research further.

### Phase 4: Implementation

**Fix the root cause, not the symptom**:

1. **Create a Failing Test Case**
   - Simplest reproduction
   - Automated test if possible; throwaway script if framework unavailable
   - Prepare before fixing
   - Use test-driven-development to write a proper failing test

2. **Implement Single Fix**
   - Address the identified root cause
   - One change at a time
   - Do not bundle opportunistic improvements
   - Do not bundle refactoring

3. **Verify the Fix**
   - Does the test pass?
   - Are other tests still passing?
   - Is the problem truly resolved?
   - Use verification-before-completion before claiming success

4. **When Fix Fails**
   - Stop
   - **Count attempted fixes**
   - If fewer than 3, return to Phase 1 and re-analyze with new information
   - **If 3 or more, stop and question the architecture (next section)**
   - Do not attempt a 4th fix without an architectural discussion

5. **Question Architecture After 3+ Failures**

   Patterns indicating architectural issues:
   - Each fix reveals new shared state, coupling, or problems elsewhere
   - Fixes require "major refactoring"
   - Each fix shifts symptoms to another location

   **Stop and question premises**:
   - Is this pattern fundamentally sound?
   - Are you persisting out of momentum?
   - Should the architecture be redesigned instead of patching symptoms?

   **Discuss with the user before attempting further fixes.**

   This is not a failure of hypothesis; it is the conclusion that the **architecture is flawed**.

## Red Flags — Stop and Follow Process

Stop whenever thinking:

- "Quick fix now, investigate later"
- "Let's change X and see what happens"
- "Let's change multiple things and run the tests"
- "Skip tests and verify manually"
- "It's probably X, so fixing it"
- "Not 100% sure, but this might work"
- "Pattern is X, but applying my slight variation"
- "The main issue is this" (listing fixes without investigating)
- Proposing solutions before tracing data flow
- **"Just one more attempt" (already tried 2+)**
- **Each fix creates a new problem elsewhere**

**All of these mean: Stop. Return to Phase 1.**

**If failed 3+ times**: Question the architecture (Phase 4.5).

## User Signals That You're Doing It Wrong

- "Is that even happening?" — Assumed without verifying
- "Does that tell us anything?" — Should have added diagnostic logging first
- "Stop guessing" — Proposing fixes without understanding
- "Think carefully" — Question premises rather than symptoms
- "Are you stuck?" (frustration) — Approach is failing

**When you see these signals, stop and return to Phase 1.**

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Simple problem, process not needed" | Simple problems have root causes too. For simple bugs, process is fast |
| "Emergency, no time for process" | Systematic debugging is faster than flailing guesses |
| "Try this first, then investigate" | First fix sets the tone. Do it right from the start |
| "Verify fix works, then write tests" | Untested fixes regress. Writing tests first proves the fix |
| "Fixing together saves time" | Cannot isolate what worked. Introduces new bugs |
| "Reference is long, copying the gist" | Partial understanding guarantees bugs. Read completely |
| "I see the issue, so fixing it" | Seeing a symptom is different from understanding the root cause |
| "Just one more try" (after 2+ fails) | 3+ failures signal architectural problems. Question the pattern, not the fix |

## Quick Reference

| Phase | Action | Completion Criteria |
|---|---|---|
| **1. Root Cause** | Read errors, reproduce, check changes, gather evidence | Understand what and why |
| **2. Pattern** | Find working examples, compare | Identify diffs |
| **3. Hypothesis** | Hypothesize, test minimally | Confirmed or formed new hypothesis |
| **4. Implementation** | Create test, fix, verify | Bug resolved and tests pass |

## When There Truly Is "No Root Cause"

If systematic investigation proves the issue is genuinely environmental, timing-dependent, or external:

1. Process is complete
2. Document what was investigated
3. Implement appropriate handling (retry, timeout, error messages)
4. Add monitoring and logging for future troubleshooting

**Note**: 95% of "no root cause" claims are simply insufficient investigation.

## Supporting Techniques

- [root-cause-tracing.md](root-cause-tracing.md) — Trace up the call stack to find the original trigger
- [defense-in-depth.md](defense-in-depth.md) — Add multi-layer validation after finding the root cause
- [condition-based-waiting.md](condition-based-waiting.md) — Replace arbitrary waits with condition polling
