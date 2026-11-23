---
name: brainstorming
description: >-
  Use only when the user explicitly requests this legacy brainstorming skill by name.
  For ordinary design questions, let pstack select the design workflow.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Clarify Intent and Design

Use brainstorming to reduce ambiguity, not as a mandatory ceremony. If the user has already given
the purpose, scope, constraints, and success criteria, do not ask them to repeat it.

Do not recursively invoke brainstorming while changing this skill.

Before choosing a design, consult relevant project ADRs using
[architecture-decision-records](../architecture-decision-records/SKILL.md). Reuse accepted decisions
within their scope. When a significant lasting choice emerges, use that skill to record its context,
real alternatives, rationale and consequences, reflecting the existing design approval rather than
adding a duplicate gate. Routine local changes need no ADR. Research/planning-only requests do not
authorize project-local writes; keep decision candidates in the requested artifact until authorized.

## Choose a route

### Direct

Use direct execution when:

- the change is confined to an existing flow
- expected behavior is clear
- there is no important design choice or external operation
- the scope and verification can be estimated

Read the relevant files. If implementation was requested, implement, verify, and report; otherwise
deliver the requested design, findings, or decisions without product edits. Do not create a
specification or approval gate just for formality.

### Bounded

Use bounded design when an existing flow is changing but one or more implementation choices remain.
Write a short design containing purpose, files, chosen approach, rejected alternatives, risks,
error handling, and verification. If implementation was requested and no consequential choice
remains, use that design as the implementation plan without asking for another approval. Otherwise,
deliver the requested design, findings, or decisions without product edits.

Ask one question only when the unresolved choice would change behavior, scope, data, permissions,
or external side effects. After the answer, continue with the agreed design.

If a bounded change has a consequential unresolved design risk (for example, a migration,
permission change, or hard-to-reverse side effect), run `design-checkpoint-review` on the draft
before implementation. A public behavior change or multiple layers alone do not establish such a
risk; identify the actual failure and impact.

### Architectural

Use the architectural route when a new subsystem, public contract, migration, authentication
change, or multiple layers introduce consequential design choices that remain unresolved:

1. state purpose, non-goals, constraints, and success criteria
2. compare two or three viable approaches
3. recommend one and describe data flow, error handling, and verification
4. create a specification or plan only when it will be used
5. obtain a decision only for an unresolved consequential choice; an existing user decision suffices

Before presenting a consequential design for approval, use `design-checkpoint-review` to check the
draft against the original request, available issue and repository rules, and likely side effects.
Keep the review focused on the design; do not turn minor bounded choices into a mandatory gate.

Do not make child agents, preview tabs, or MAD mandatory when the scope does not justify them.

### Spike

Use a spike or prototype when explicitly requested or needed to explore or validate a meaningful
design or implementation decision, not as a default requirement. Define the question, small experiment, and success criteria.
Keep disposable experiments separate from product changes.

## When to ask the user

Ask before execution when:

- an irreversible operation, external endpoint, publication, commit, push, or `chezmoi apply` is
  required
- the request leaves a consequential behavioral choice unresolved
- purpose, scope, or success criteria are missing and guessing risks rework
- the work must expand beyond the original request

A concrete request is already permission to begin that requested scope. Do not ask “may I start?”
when no decision is needed.

## Conversation flow

1. Read the request and relevant existing files.
2. Extract purpose, constraints, scope, and success criteria.
3. Ask only for missing high-impact information.
4. Present the smallest useful design when choices remain.
5. Treat the user's answer as a new constraint.
6. For an implementation request, continue from the design or spike to implementation and
   verification once it has served its purpose, without another approval if no consequential choice
   or permission remains. Do not expand an explicitly design-only or research-only request into
   implementation.

Use explicit safe assumptions instead of an endless questionnaire when the assumption is reversible and
does not change the user's outcome.

## Children and related skills

Child agents are optional. Use them only when independent research, parallel implementation, a
separate perspective, or user-requested delegation is worth the coordination cost.

- Small sequential plans: `executing-plans`.
- Independent tasks, multiple children, strict artifacts, or required isolation:
  `multi-agent-development`.
- Finalized multi-stage architecture: `writing-plans`.
- Consequential design checkpoint before implementation: `design-checkpoint-review`.
- Unknown bug cause: `systematic-debugging`.

This skill does not automatically chain an execution skill. The parent chooses the execution route;
the design checkpoint applies only when the design has consequential risks.

## Re-evaluate when complexity appears

Do not switch to a heavier route merely because an incidental detail appeared. Continue if the
purpose, scope, risk, and verification remain explainable. Re-plan or ask when the new complexity
introduces a consequential design choice, destructive operation, or dependency on another owner.

## Minimal design format

Use only the fields needed:

- purpose
- scope and files
- selected approach
- rejected alternatives and why
- risks and error handling
- verification
- unresolved decisions

Do not create a specification, diagram, or review loop for a trivial change.

## Completion

- Direct: for implementation requests, report the change and fresh verification; otherwise deliver
  the requested design, findings, or decisions without product edits.
- Bounded: for implementation requests, implement the agreed design and report evidence; otherwise
  deliver the requested design, findings, or decisions without product edits.
- Architectural: for implementation requests, continue through the selected execution route;
  otherwise deliver the requested specification or plan.
- Spike: report evidence, limitations, and recommendation; for implementation requests, continue
  to implementation and verification when no consequential choice or permission remains.

Never claim success without fresh verification or clearly state what remains unverified.
