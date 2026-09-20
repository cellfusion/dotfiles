---
name: brainstorming
description: >-
  Clarify intent and design only when a request leaves meaningful choices unresolved. Avoid formal
  gates for clear local changes; ask the smallest question that prevents costly rework.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Clarify Intent and Design

Use brainstorming to reduce ambiguity, not as a mandatory ceremony. If the user has already given
the purpose, scope, constraints, and success criteria, do not ask them to repeat it.

Do not recursively invoke brainstorming while changing this skill.

## Choose a route

### Direct

Use direct execution when:

- the change is confined to an existing flow
- expected behavior is clear
- there is no important design choice or external operation
- the scope and verification can be estimated

Read the relevant files, implement, verify, and report. Do not create a specification or approval
gate just for formality.

### Bounded

Use bounded design when an existing flow is changing but one or more implementation choices remain.
Write a short design containing purpose, files, chosen approach, rejected alternatives, risks,
error handling, and verification. If no consequential choice remains, use that design as the
implementation plan without asking for another approval.

Ask one question only when the unresolved choice would change behavior, scope, data, permissions,
or external side effects. After the answer, continue with the agreed design.

### Architectural

Use the architectural route for a new subsystem, multiple layers, public contracts, migrations,
authentication, or several valid designs:

1. state purpose, non-goals, constraints, and success criteria
2. compare two or three viable approaches
3. recommend one and describe data flow, error handling, and verification
4. create a specification or plan only when it will be used
5. obtain a decision before implementation

Do not make child agents, preview tabs, or MAD mandatory when the scope does not justify them.

### Spike

Use a spike to answer whether something is possible or which option is better. Define the question,
small experiment, and success criteria. Keep disposable experiments separate from product changes.

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
6. Implement and verify the selected design.

Use explicit safe assumptions instead of an endless questionnaire when the assumption is reversible and
does not change the user's outcome.

## Children and related skills

Child agents are optional. Use them only when independent research, parallel implementation, a
separate perspective, or user-requested delegation is worth the coordination cost.

- Small sequential plans: `executing-plans`.
- Independent tasks, multiple children, strict artifacts, or required isolation:
  `multi-agent-development`.
- Finalized multi-stage architecture: `writing-plans`.
- Unknown bug cause: `systematic-debugging`.

This skill does not automatically chain the next skill. The parent chooses the execution route.

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

- Direct: report the change and fresh verification.
- Bounded: implement the agreed design and report evidence.
- Architectural: leave the approved specification/plan and hand off to the selected route.
- Spike: report the experiment, evidence, limitations, and recommendation.

Never claim success without fresh verification or clearly state what remains unverified.
