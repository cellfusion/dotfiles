---
name: brainstorming
description: >-
  Clarify intent and architecture for undetermined changes. Do not use for clear, localized
  changes; ask questions, design, and seek approval only to the necessary extent.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Clarifying Change Intent and Designing to the Necessary Extent

Brainstorming is a skill to assist decision-making, not an approval gate required for every change.
If the user has clearly specified the goal, target, constraints, and completion criteria, proceed directly to work without re-asking.
When modifying this skill itself, do not invoke brainstorming recursively.

## Determining the Path

Decide which path to handle the request with. Declare the category to the user only when questions or deliverables differ based on the path. Categorization is a recommendation; the parent agent may choose a lighter or heavier path based on safety and workload.

### direct

Proceed with standard development workflows without design approval if:

- Changes are confined to existing routines
- Desired behavior is unambiguous from the request
- No critical design choices or external actions exist
- Scope of impact and verification methods are predictable

Steps are: read relevant files, make modifications, verify, and report results. Do not generate design documents or confirmation questions.

### bounded

Used when altering existing behavior but design or implementation choices remain. Summarize target, direction, files touched, and verification methods in a few lines. If no unresolved choices remain, treat this summary as the working plan and proceed to implementation. Do not demand redundant re-approval of the user's initial request.

Only if behavioral alternatives have not been determined by the user, ask the single most consequential question. After receiving the response, present a concise design and implement according to agreed content.

### architectural

Used for new subsystems, multi-layer changes, or modifying contracts on which other components depend. Follow this general sequence, omitting documents according to workload:

1. Clarify goals, non-goals, constraints, and success criteria
2. Compare 2-3 major options and state a recommendation
3. Design architecture, data flow, error handling, and verification methods
4. Create spec and plan if necessary
5. Obtain approval on design choices before implementing

Creating specs, having separate agents evaluate specs, previewing, and using MAD are not automatic requirements. Choose based on design scale, risk, and user preference.

### spike

Used for requests cheaply verifying "is it feasible?" or "which option is better?". Define the question, what to try, and success criteria concisely, confirming with user if necessary before investigating. Never treat throwaway prototypes or exploratory code as production changes.

## When Approval is Required

Seek confirmation from the user prior to execution only when:

- Performing hard-to-reverse actions: destructive commands, external endpoints, billing, public publishing, commits, applies
- Choices undefined in request alter outcomes or behavior
- Goals, targets, or success criteria are insufficient, where guessing risks major rework
- Direction or scope must change mid-flight

Do not create ceremonial gates solely to ask "may I start implementing?" A user requesting a specific change already authorizes implementing within that scope.

## How to Conduct Dialogue

1. Read the request and relevant existing files
2. Confirm goals, constraints, and success criteria. Do not repeatedly ask what is already written in the request
3. Only if information is missing, ask questions one by one starting with the highest impact
4. When sufficient clarity is reached, present minimal design required for the path
5. Treat user answers and design as new constraints
6. After implementation, verify change scope and results

Questions may offer choices, but do not artificially complicate problems to add options. When proceeding under explicit safe assumptions is preferable to endless questions, state the assumption and proceed.

## Child Agents and Other Skills

Delegating to child agents is optional. Use only when:

- Independent investigation or implementation can proceed concurrently
- Long investigations warrant separation from parent work
- Reviews from distinct perspectives are required
- User explicitly requested delegation

Never stop work simply because child agents cannot be spawned. If parent can directly investigate, implement, or review, use that route.

- Small plans are executed serially by parent via `executing-plans`
- Use `multi-agent-development` only when independent tasks, worktrees, multiple children, or strict artifact contracts are required
- Use `writing-plans` only when architectural design has solidified and multi-phase implementation plans are needed
- Use `systematic-debugging` if the root cause of a bug is unverified

This skill does not automatically chain other skills. The parent agent decides subsequent steps.

## Escalating to a Heavier Path

If complexity surfaces during execution, there is no need to abruptly halt and jump to a heavier path. Check:

- Is the added complexity necessary for the original goal?
- Can change scope and verification methods still be explained?
- Have destructive actions or external blast radiuses increased?

If explainable and risks have not grown, continue on the current path. If unexplainable or design choices have expanded, present differences and options to the user before changing paths.

## Minimal Design Format

When presenting a design, include only necessary items from:

- Goal
- Routines and files to modify
- Adopted strategy
- Rejected strategies and rationale
- Error handling
- Verification methods
- Unresolved choices

Do not wrap simple changes in specs, plans, diagrams, and review rounds. Even when creating documents for complex changes, writing documentation is never an end in itself.

## Completion Criteria

- direct: Report modification and verification results, then finish
- bounded: Implement according to agreed design, report verification results, then finish
- architectural: Produce necessary design documents/plans and hand off to user's chosen execution route
- spike: Report findings and recommendations, then finish

Run appropriate tests, lints, diffs, or artifact inspections before claiming success. Report unverified items explicitly.
