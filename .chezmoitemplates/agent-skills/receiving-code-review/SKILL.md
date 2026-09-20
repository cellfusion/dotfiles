---
name: receiving-code-review
description: >-
  Use when receiving code review feedback before implementing suggestions.
  Especially critical when feedback is ambiguous or technically questionable.
  Verify before acting; neither sycophantically agree nor blindly implement.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Receiving Code Review

## Overview

Code review is a technical evaluation, not an emotional performance.

**Core**: Verify before implementing. Ask before assuming. Technical correctness over social comfort.

## Response Pattern

```
When receiving review feedback:

1. Read: Read the feedback to the end without reacting
2. Understand: Restate the requirement in your own words (ask if unable)
3. Verify: Check against the reality of the codebase
4. Evaluate: Is this technically sound for this codebase?
5. Respond: Technical confirmation, or reasoned pushback
6. Implement: One item at a time, testing each
```

## What to Delegate to Children

The parent handles receiving findings, clarifying ambiguous items with the user, deciding whether to push back, consulting on conflicts with prior user decisions, and ordering implementation.

Delegate the following 3 tasks to children:

- **Verifying findings against codebase** — Invoke the `researcher` role through Paseo or the native role path. Resolve it through `agent-config` when using Paseo. Pass finding text and absolute paths of files to read. The child returns what was confirmed vs. what could not be confirmed.
- **Call site verification** — Used for YAGNI checks against "implement it properly" requests. Invoke the same `researcher` role. Do not switch backends merely because a provider-native wrapper is unavailable.
- **Implementing fixes** — Use MAD's `implement` recipe. Pass findings, review package, and absolute paths to target files. The child executes TDD and re-review.

The parent must not write fixes directly. Fixes written by the parent do not undergo independent reviewer judgment, and the diffs and test logs remain in parent context, re-read on every subsequent turn.

## Prohibited Responses

**Never write**:
- "You're absolutely right"
- "Great point!", "Awesome feedback!"
- "I will implement that right away" (before verification)

**Instead**:
- Restate the technical requirement
- Ask clarifying questions
- Push back with technical rationale if incorrect
- Begin working directly (actions over words)

## Handling Ambiguous Feedback

```
If even a single item is ambiguous:
  Stop — do not implement anything yet
  Ask for clarification on the ambiguous item

Rationale: Items are often interdependent. Partial understanding produces buggy code
```

Example:

```
User: "Fix items 1 through 6"
Understood: 1, 2, 3, 6. Ambiguous: 4, 5.

❌ Wrong: Implement 1, 2, 3, 6 now and ask about 4, 5 later
✅ Right: "Understood 1, 2, 3, and 6. Before starting, I would like to clarify 4 and 5."
```

## Handling by Source

### From User

- **Trust** — Implement once understood
- If scope is ambiguous, **still ask**
- Omit agreeable fluff
- Jump directly to action or return only technical confirmation

### From External Reviewer

```
Before implementing:
  1. Is this technically sound for this codebase?
  2. Does this break existing functionality?
  3. Is there an intentional historical reason for the current implementation?
  4. Does this hold across all supported platforms/versions?
  5. Does the reviewer possess full context?

If you believe the suggestion is wrong:
  Push back with technical rationale

If you cannot easily verify:
  Say so: "Cannot verify without X. Should we investigate, ask, or proceed?"

If it conflicts with prior user decisions:
  Consult with the user first
```

**Policy**: Treat external feedback with constructive skepticism, verifying thoroughly and politely.

## YAGNI Check for "Implement It Properly"

```
When a reviewer asks to "properly implement" something:
  Grep the codebase for actual call sites

  Unused: "This endpoint has no callers. Can we delete it instead (YAGNI)?"
  Used:   Implement it properly
```

## Implementation Order

```
For multi-item feedback:
  1. Clarify ambiguous items first
  2. Have children implement in this order:
     - Blockers (breakages, security vulnerabilities)
     - Simple fixes (typos, imports)
     - Involved changes (refactoring, logic updates)
  3. Pass each fix individually to children, having them test each
  4. Have children verify no regressions occurred
```

## When to Push Back

- Suggestion breaks existing functionality
- Reviewer lacks overall architectural context
- Violates YAGNI (unused functionality)
- Technically incorrect for this technology stack
- Historical compatibility requirements exist
- Conflicts with user's architectural decisions

**How to push back**:
- State technical rationale without defensiveness
- Ask specific, focused questions
- Point to working tests or code
- Involve the user if architectural decisions are impacted

**If you feel hesitant to push back**: Name that tension explicitly and present the observed technical conflict to the user.

## Confirming Valid Findings

```
✅ "Fixed. <What was changed>"
✅ "Resolved <specific issue> in <location>"
✅ Fix directly and demonstrate with code

❌ "You are completely right"
❌ "Good catch!"
❌ "Thank you for noticing"
❌ Expressions of gratitude in general
```

**Why omit gratitude**: Actions speak. Fixing the issue is sufficient proof of having received the feedback.

**If you catch yourself typing "thank you"**: Erase it. State what was fixed instead.

## When Pushback was Mistaken

```
✅ "Verified. <X> was indeed <Y>. Implementing now."
✅ "Tested and confirmed. Finding was correct; my previous understanding was incorrect due to <reason>. Fixing."

❌ Long apologies
❌ Defending why you initially pushed back
❌ Excessive explanations
```

State the factual correction and move forward.

## Common Mistakes

| Mistake | Remedy |
|---|---|
| Agreeable fluff | Restate technical requirement or proceed silently |
| Blind implementation | Verify against codebase first |
| Implementing in bulk without testing | Implement and test one item at a time |
| Assuming reviewer is always right | Verify it doesn't break existing features |
| Avoiding pushback | Technical correctness over social comfort |
| Partial implementation | Clarify all items before starting |
| Proceeding without verification | State constraints and request guidance |
| Writing fixes yourself | Fixes written by parent lack independent reviewer gates and bloat context; pass to children |

## Examples

**Sycophancy (Bad)**

```
Reviewer: "Delete this legacy code"
❌ "You're absolutely right. Deleting immediately."
```

**Technical Verification (Good)**

```
Reviewer: "Delete this legacy code"
✅ "Checked. The build target is 10.15+, while this newer API requires 13+.
   The legacy path is required for backward compatibility. The current implementation
   has an invalid bundle ID, so we should either fix that or decide to drop pre-13 support."
```

**YAGNI (Good)**

```
Reviewer: "Implement metrics with DB persistence, date filters, and CSV export"
✅ "Grepped the codebase. This endpoint has no callers.
   Can we remove it instead (YAGNI), or is there an intended caller I missed?"
```

## GitHub Thread Replies

When replying to inline review comments, reply directly to the review thread rather than posting a top-level PR comment (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`).
