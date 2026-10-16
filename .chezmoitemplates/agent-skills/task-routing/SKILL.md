---
name: task-routing
description: >-
  Select direct work, internal delegation, or multi-agent delivery when the route is unclear.
  Choose independent interaction and checkout write ownership separately; skip clear local changes.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Route a Development Request

The parent decides the goal, scope, acceptance criteria, and verification before dispatch. This
skill does not implement code or approve a design. A clear local change needs no routing ceremony.

## Make three independent decisions

1. **Execution:** direct parent work, one internal child, or multiple internal children.
2. **Interaction:** remain internal for same-repository work by default. Delegate cross-repository
   ownership and explicitly independent conversations to `agent-communication`; it resolves the
   available host and live recipient identity.
3. **Writes:** use the existing checkout with disjoint scopes and one integration owner when safe.
   Delegate separate checkout ownership and isolation to `using-git-worktrees` when required.

A separate pane does not require a new worktree. A separate worktree does not require a pane,
workspace, tab, or separate CLI. Combine these only when both needs are established.

## Bounded task contract

Before any child starts, specify:

- goal, work class, trusted requirement/plan paths
- exact allowed files and non-goals
- acceptance criteria and verification commands, including who runs them
- cwd, repository, committed base SHA, execution route, and worktree owner if applicable
- required result/artifact paths and finite retry/review limits
- consequential decisions that require the user rather than guessing

Use the shared audit trail to record the route, ownership decision, and safe artifact references.
Do not invent provider/model metadata or use a legacy transport admission wrapper. Keep existing
model and permission defaults; the task contract does not choose a provider, model, or permission
bypass. Do not pass conversation history, credentials, or unrelated plans.

If scope or acceptance is unclear, inspect the repository first. Use an available read-only internal
research role only for a genuinely unmapped slice. Resolve a consequential unknown before starting
a writer; a router cannot approve architecture or expand scope.

## Choose the smallest useful route

### Direct

Implement directly when one known flow and a handful of files can be changed and verified safely.
Use `brainstorming` only for a real unresolved design choice, not to restate a clear request.

### Single child

Use one internal child only when a distinct ownership/context boundary justifies it, not for a small
edit or a direct question already open in the parent. Do not add plan-auditor or multi-round delivery
machinery for one bounded task.

1. Fix the child contract and artifact expectations.
2. If write isolation is needed, delegate it to `using-git-worktrees` from the recorded committed
   parent base. Otherwise explicitly assign disjoint writes in the existing cwd.
3. Dispatch through the runtime's actual internal tool, using its documented cwd and role interface.
   Read live tool help if unclear; do not substitute a separate CLI or guess a cwd parameter.
4. The child changes only its scope and returns changes, evidence, and unresolved conditions.
   Commit, push, apply, dependency setup, and external writes still require explicit authorization.
5. The parent independently checks artifacts, changed files, scope, acceptance, and verification.
   In shared work, children skip tests/builds/linters/formatters; the integration owner runs once
   after all writes land. Do not call a child success message verification.

### Delivery

Use `writing-plans` for finalized multi-stage work and `multi-agent-development` for genuinely
independent implementation or review slices. Map dependencies/shared contracts before dispatch;
parallelize independent slices, serialize only real dependencies. Do not delegate the top-level
integration decision. An existing plan does not automatically justify multiple phases or agents.

## Work class

- **mechanical:** a fixed local update following existing patterns; no new design.
- **routine:** a few files within a settled design.
- **integration:** connect callers/layers with explicit contracts and error handling.
- **architectural:** consequential new contracts or multiple valid designs; settle those decisions
  before implementation, using design review where required.

Use the runtime's available role most specific to the task. Do not turn model names or effort
levels into roles. Agent/provider configuration used by other tools remains separate from routing.

## Independent CLI interaction

Delegate independent interaction to `agent-communication`. It resolves the supported environment,
recipient, readiness and bounded submission contract without changing models or permissions.
Delegate checkout creation, inspection and cleanup to `using-git-worktrees`; an interaction host
does not establish checkout ownership. Do not launch, detect or select a host in this router.

For another repository, resolve that repository's actual owner through `agent-communication`;
do not use a child in the parent's checkout to edit another repository. Send only the bounded
contract and scope. Each owner verifies locally; the parent verifies cross-repository integration.

For GitHub PR review, delegate launch and environment selection to `pr-review`. A supplied prepared
context stays in its existing validated environment: do not create another checkout, terminal,
pane or session. Use `requesting-code-review` for fixed review packages and finding adoption.

## Bounded escalation

A deterministic failure (missing dependency, invalid result, timeout, known test failure) needs an
evidence-based correction or decision, not an escalation child. For semantic uncertainty, an
available read-only reviewer/judge may assess the fixed inputs and permitted options. It cannot
change provider, permissions, ownership, scope, or the attempt budget.

Record the initial attempt and a finite repair limit before dispatch. Default to one repair attempt
for a single task; use the bounded MAD review policy for delivery. Preserve each failed attempt and
its artifacts. Do not relaunch after unknown/timeout until liveness and ownership are established.
At the limit, report unresolved evidence and the precise required decision; never retry indefinitely.
