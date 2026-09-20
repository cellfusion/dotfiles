---
name: task-routing
description: >-
  Select the execution route, work class, and implementation role for a development request.
  Skip it for clear local changes; use it only when direct, single-agent, and delivery paths need to be distinguished.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Route a Request to an Execution Path

task-routing is the entry point for turning a user request into an implementation task packet. It does not implement code, approve designs, or execute the MAD strict contract. Skip it for a clear local change: the parent may implement directly or start one lightweight `implementer` child.

## Task packet

Use a packet with finite values. Do not put free-form provider or model choices in it.

```json
{
  "route": "direct|single|delivery",
  "workClass": "mechanical|routine|integration|architectural",
  "role": "implementer|architectural-implementer",
  "complexity": "simple|routine|complex|critical",
  "goal": "...",
  "writeScope": ["..."],
  "acceptanceCriteria": ["..."],
  "verification": ["..."],
  "needsBrainstorming": false,
  "needsUserDecision": false,
  "confidence": "high|medium|low",
  "reason": "..."
}
```

Do not set `confidence: high` while `writeScope`, `acceptanceCriteria`, or `verification` is unknown. Set `needsUserDecision: true` when guessing would change the result.

## Who creates the packet

- If the request is clear and confidence is high, the parent creates the packet directly
- If confidence is medium or low, or several routes are plausible, start the read-only `intake-router` role
- Give `intake-router` only the raw request and the minimum repository context. It returns a packet under its schema and never changes code or configuration
- Resolve the `intake-router` launch from `agent-config.routingSelection`. Do not let the router choose a provider, model, or effort
- If the router returns `needsUserDecision: true` or `confidence: low`, do not create an implementation child; ask the parent to resolve the decision

## Route selection

### direct

The parent implements directly when:

- one existing flow is being changed
- the change touches one or two files
- the requested behavior is clear
- there is no external operation, public contract, or design choice

### single

Delegate one implementation to one child. Do not start full MAD, plan-auditor, or a task review loop.

- the change is clear but should be isolated from the parent's context
- implementation and verification should run in a separate session
- there is one task and no parallelism

The single-child procedure is:

1. Create a packet with `confidence: high`, `route: single`, `workClass`, `writeScope`, `acceptanceCriteria`, and `verification`
2. If the child writes files, create one dedicated Paseo worktree; never let it write to the parent's working tree
3. Pass only the `implementer` prompt, schema, and packet absolute paths. Do not pass the full conversation or an unrelated plan
4. Add the prompt overlay for the packet's `workClass`
5. The child implements, tests, commits, and writes a report
6. The parent independently checks status, commit, diff, changed files, scope, and test output
7. If the result cannot be adopted, use evidence to choose retry, `escalation-judge`, direct repair, or a user decision

A single-child launch failure is not a strict MAD run failure. Do not add unlimited children or switch backends; return to direct implementation or report the situation to the user.

### Single implementer launch contract

When a single route starts a write child, the parent follows this order:

1. Save the packet as a mode `0600` absolute file and validate it with the `intake-router` schema
2. Resolve the launch with `agent-config resolve --role implementer --provenance mad-dispatch --complexity <packet.complexity> --round 0`. Do not reconstruct provider, model, effort, or features in the parent
3. Create one Paseo worktree and pass its `workspaceId` to child creation
4. Pass only the `implementer` prompt, schema, packet absolute path, and work-class overlay in `initialPrompt`. Do not pass the user's full conversation, unrelated repository content, or another task's artifacts
5. Call `mcp__paseo__create_agent` exactly once and pass `notifyOnFinish` and launch settings unchanged. Do not substitute the CLI or another backend
6. After completion, independently check `status`, `baseHead`, commit, `changedFiles`, clean worktree state, acceptance criteria, and verification
7. If the result cannot be adopted, do not send unlimited follow-ups to the same child; choose `escalation-judge`, direct repair, or a user decision

The single route does not use MAD plan-audit, waves, or task review/fix admission. It still requires independent validation of the child commit, diff, tests, and scope.

### delivery

Use `writing-plans` and `multi-agent-development` only when multi-stage design, implementation, and review are needed.

- independent tasks can run in parallel
- worktree isolation is required
- multiple layers or a public contract must be integrated
- task review and final review are required

## Work-class selection

### mechanical

Follow the existing implementation pattern exactly. String replacements, path changes, and small fixed-shape edits belong here. Do not add abstractions or redesign behavior; stop or escalate when a question appears.

### routine

Change a few files within the existing design. Inspect the target code, existing tests, and acceptance criteria before implementing.

### integration

Connect multiple layers, packages, or callers. Check contracts, data flow, error handling, and integration tests. Do not guess how components connect.

### architectural

Use this for a new subsystem, public contract, schema, authentication, migration, or multiple valid design options. Do not let the implementer invent the design. Run `spec-author`, `plan-author`, and `plan-auditor` first, then start `architectural-implementer` or a strong `implementer`.

## Role selection

Use the common `implementer` role with a work-class overlay when the artifact contract, permissions, and stop conditions are the same. Use a separate role only when one of these changes:

- whether design decisions are allowed
- write scope or permissions
- artifact schema
- review path or stop conditions

Model, effort, and attempt level belong to `attemptPolicy`, not to role names. When `escalation-judge` is used, it may recommend a level and work class but must not freely choose a provider or model.

## User decisions and brainstorming

Ask the user only when:

- the requested behavior is not determined by the request
- scope, a public contract, a destructive action, or an external side effect would change
- an architectural design option remains
- confidence is low and no safe assumption is available

When `needsBrainstorming` is true, clarify purpose, constraints, and success criteria before using brainstorming. Do not start brainstorming for a clear local change.

## Terminal conditions

- `direct`: the parent implements and runs appropriate verification
- `single`: start one implementer child and have the parent adopt its artifacts
- `delivery`: hand off to spec, plan, audit, and MAD delivery
- `needsUserDecision`: create a decision request and do not start implementation

Do not ask endless routing questions. Once goal, scope, acceptance criteria, and verification are sufficient, continue to the selected route.
