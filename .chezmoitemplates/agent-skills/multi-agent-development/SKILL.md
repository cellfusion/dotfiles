---
name: multi-agent-development
description: >-
  Run multiple child agents, parallel tasks, isolated worktrees, or independent review through the
  configured Paseo CLI or MCP backend. Do not use it for a single local task or ordinary conversation.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Use Multi-Agent Development Only When It Helps

MAD is an execution recipe for a parent coordinating multiple children. It is not a requirements
interpreter, complexity oracle, or replacement for the parent's decisions.

## When to use MAD

Use MAD only when at least one is true:

- independent tasks can run in parallel
- separate research, implementation, and review improves quality or time
- each task requires an isolated worktree
- long-running work must be removed from the parent's conversation
- the user explicitly requests multiple agents

Do not use MAD when:

- one task can be implemented directly
- a small sequential plan fits `executing-plans`
- child coordination costs more than the work
- the parent can inspect the diff and verification directly

Not using MAD is a valid result. Choose direct work or `executing-plans` when it is safer or faster.

## Parent responsibilities

Only the parent decides:

- whether MAD is appropriate
- recipe, tasks, dependencies, and concurrency
- child role, scope, artifacts, and complexity
- review adoption, retries, escalation, and stopping
- when to ask the user

Never adopt a child based only on its success message. Independently inspect artifacts, diff, tests,
scope, status, and schema.

## Recipes

| Recipe | Use when | Completion |
|---|---|---|
| `research` | independent research perspectives are useful | parent integrates all evidence |
| `fanout` | independent implementation tasks can run in parallel | all adoption decisions are complete |
| `review` | independent review lenses are needed | package and verdict are verified |
| `delivery` | spec, plan, implementation, task review, and final review are required | every phase and integration is verified |
| `refine` | a bounded existing artifact needs improvement | scope-limited diff is verified |

`spec` and `plan` are phases of delivery, not independent recipes. The parent may write a small
spec or plan directly.

## Lightweight routes

Do not start full delivery automatically:

1. **single child** for one isolated research or implementation task
2. **fanout** for independent children
3. **delivery** only when multiple phases and integration gates are justified

A single child can use the ordinary Paseo route without the strict MAD contract. Use the strict
contract only for a multi-child run that needs its state and artifact guarantees.

## Before a strict run

Record:

- run purpose and recipe
- each node's input, output, responsibilities, and allowed write scope
- dependencies and parallel waves
- success and stop conditions
- required user decisions
- selected backend and whether fallback is allowed

Do not delegate this decision to a child. The configured backend is either `paseo-cli` or
`paseo-mcp`; select one at run start and keep it for the entire run. If the selected strict backend
is unavailable before the run starts, work directly or ask the user. Do not switch backends or retry
the same create after a strict run has started.

## Strict delivery preparation

Apply the strict contract only after choosing a strict MAD delivery run. Initialize the distributed
script paths from the installed skill directory and use the current shared manual contract:

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
MAD_BACKEND="${MAD_BACKEND:-paseo-cli}"
MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"
MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"
MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"
MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"
MAD_OUTCOME_LOG="${MAD_OUTCOME_LOG:-$MAD_STATE_DIR/metrics/attempt-outcomes.jsonl}"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
```

The strict contract owns provider/model discovery, request validation, state, call logs, worktrees,
review scope, escalation, and outcome recording. Run the dependency gate before the `plan-auditor`;
the `plan-auditor` is a one-shot gate before the first implementer. Do not reconstruct provider, model, features, or request payloads in the parent. Use the installed `paseo-cli` backend by default and select
`paseo-mcp` explicitly when provider-specific features are required.

## During execution

For a strict run:

1. create unique run and attempt directories; never overwrite another attempt
2. fix role, prompt, schema, scope, and base for each child
3. record create, wait, stop, worktree, and retry counts
4. validate every child artifact against schema and scope
5. record the parent's adoption decision at each phase boundary
6. do not widen review scope without a new decision
7. treat timeout, transport failure, and unknown state as unresolved, never successful
8. stop when the configured attempt or round limit is reached

Use `mad-worktree` for strict worktree isolation and pass the returned absolute path to the selected
Paseo workspace. Do not let Paseo silently create a different Git worktree.

## Review and fix boundaries

Use a fixed review package and immutable base/head identity for each review. Keep review findings in
the configured review artifacts. A fix child may change only files in the approved scope and must
produce fresh verification. A second review must use a fresh package; never review a stale diff.

## Completion

The parent independently validates the final run state, adopted artifacts, tests, review verdict,
changed files, scope, integration, and worktree removal. A child report is not completion evidence.

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
