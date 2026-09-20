---
name: task-routing
description: >-
  Select the execution route, work class, and implementation role for a development request.
  Skip it for clear local changes; use it only when direct, single-agent, and delivery paths need to be distinguished.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

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

## Route admission audit

Record every admission decision, including `direct`, before execution. Initialize the local recorder once:

```bash
TASK_ROUTING_SCRIPTS="${TASK_ROUTING_SCRIPTS:-$HOME/.agents/skills/task-routing/scripts}"
MAD_ROUTE_ADMIT="$TASK_ROUTING_SCRIPTS/mad-route-admit"
MAD_ROUTE_RECORD="$MAD_SCRIPTS/mad-route-record"
MAD_ROUTE_LOG="${MAD_ROUTE_LOG:-$HOME/.local/state/mad/metrics/route-decisions.jsonl}"
```

Run the admission wrapper before starting the selected path. It validates the finite packet, adds a `routeId`, writes the mode `0600` route decision, and emits the admitted packet:

```bash
"$MAD_ROUTE_ADMIT" \
  --packet "$PACKET" --output "$ADMITTED_PACKET" \
  --route-record "$MAD_ROUTE_LOG" \
  --backend "$MAD_BACKEND" --provider "$PROVIDER" \
  --model "$MODEL" --effort "$EFFORT"
```

For `direct`, omit backend/provider/model/effort and set the packet route to `direct`. Use the admitted packet for the selected path and pass its `routeId` into any child outcome record. Do not include the raw request, prompt, repository contents, credentials, or URLs. This log is the denominator for route statistics; child attempt results belong in `mad-attempt-outcome`.

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
2. Create one Paseo worktree and obtain its `workspaceId`
3. Run `~/.agents/skills/task-routing/scripts/single-implementer prepare` with the packet, config, project, snapshot, workspace ID, attempt directory, implementer prompt, and schema. The default backend is `paseo-cli`; it resolves the launch and writes a private `single-cli.json`
4. Read and validate `single-create.json`; do not reconstruct provider, model, effort, or features in the parent
5. For the `paseo` backend, call `mcp__paseo__create_agent` exactly once with that request. Do not substitute another backend in that mode
6. For the `paseo-cli` backend, run `~/.agents/skills/task-routing/scripts/single-implementer run-cli --request <single-cli.json>`. The CLI request must use a CLI-compatible selection with empty provider features
7. After completion, independently check `status`, `baseHead`, commit, `changedFiles`, clean worktree state, acceptance criteria, and verification
8. If the result cannot be adopted, do not send unlimited follow-ups to the same child; choose `escalation-judge`, direct repair, or a user decision

The single route does not use MAD plan-audit, waves, or task review/fix admission. It still requires independent validation of the child commit, diff, tests, and scope.

The CLI backend is the default transport for both single route and strict MAD. Use `--backend paseo` explicitly when the MCP path is required. CLI is not a fallback after a run has started, and a CLI launch must not silently discard provider features.

## Escalation judge

Use `escalation-judge` only when a failed attempt or review result requires semantic judgment. Do not start it for deterministic failures such as timeout, invalid schema, missing commit, or a known test failure.

1. Save the attempt result, review findings, test evidence, work class, current level, and available levels as absolute read-only inputs
2. Resolve `escalation-judge` through `agent-config` with `--provenance escalation` and the `escalationSelection` launch policy
3. Give the judge only those inputs and its prompt/schema; it returns an `escalation` packet
4. Run `~/.agents/skills/multi-agent-development/scripts/escalation-policy` to validate the packet against the current level, maximum level, work class, and target role
5. For a permitted next attempt, run `mad-escalation-controller`, then call `agent-config resolve --role <role> --provenance mad-fix --complexity <complexity> --work-class <workClass> --round <round> --attempt-level <attemptLevel>` and pass the resolved launch unchanged
6. For `ask_user` or `stop`, do not create a child; preserve the evidence and request the decision or stop the run

The judge recommends an action and level. It never chooses a provider or model directly, and it cannot increase the attempt budget.

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
