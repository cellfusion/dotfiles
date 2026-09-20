---
name: writing-plans
description: >-
  Turn finalized requirements and architecture into an actionable implementation plan before coding.
  Use it only for multi-stage work where the plan will guide execution and verification.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Write an Implementation Plan

A plan is a coordination artifact, not a substitute for understanding. The parent owns the purpose,
assumptions, design decisions, and adoption of review feedback.

## When to use

Use this skill when requirements and architecture are sufficiently settled and implementation has
multiple stages, dependencies, or integration boundaries. Do not create a formal plan for a clear
local edit. Split independent subsystems into separate plans when each can produce a working,
testable unit.

## Destination

Before writing, resolve the external plan directory:

```bash
PLANS="$(~/.agents/skills/_shared/scripts/agent-docs-dir plans)"
```

Create `YYYY-MM-DD-<feature-name>.md` there unless project instructions specify another destination.
The plan directory is outside the repository. Pass its absolute path to later skills.

## Plan contents

Include only what the implementation needs:

- purpose and non-goals
- approved requirements and constraints
- architecture and data flow
- ordered tasks with dependencies
- files or modules each task may change
- acceptance criteria
- verification commands and expected evidence
- rollback or migration considerations
- unresolved decisions and the user needed to resolve them

Each task should be independently understandable and small enough to verify. State complexity and
work class when the downstream routing policy requires them. Do not let an implementer invent
architecture or expand scope.

## Authoring

The parent may write the plan directly. Delegate plan writing only when independent research,
long-running decomposition, or a separate perspective is worth the cost. If a child writes it,
provide only purpose, approved specification path, known constraints, and destination. The parent
reviews and adopts the result; a child cannot make hidden design decisions.

## Review the plan

Before presenting it:

1. read it from disk
2. validate task numbering and dependencies
3. inspect file overlap within parallel waves
4. check acceptance criteria and verification commands
5. confirm the plan produces a working, testable result
6. record rejected findings and reasons

Use an existing dependency validator when available. Do not silently discard validator findings.
Reject them with rationale, preserve them as an unresolved constraint, or ask the user.

## Approval and preview

Show the plan at its external absolute path. Obtain user approval before implementation when the plan
contains unresolved consequential choices, external operations, public contracts, destructive actions,
or a worktree delegation choice. Do not add a formal approval gate merely to restate a clear user
request.

If a preview editor is used, re-read the plan after the user responds. The on-disk version is
canonical. Incorporate manual edits before handing the plan to `executing-plans` or
`multi-agent-development`.

Never run an implementation or cleanup command while waiting for approval.

## Handoff

Choose execution based on plan structure:

- sequential small plan with no parallelism: `executing-plans`
- independent tasks, isolation, or task/final review gates: `multi-agent-development`

Re-read the approved plan immediately before handoff. Pass its absolute path, not copied prose.

## Completion

A plan is complete when it is saved, self-reviewed, validated, and either approved for execution or
explicitly retained without execution. Report the path, validation evidence, unresolved decisions,
and selected downstream skill.
