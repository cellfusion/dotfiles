---
name: task-routing
description: >-
  Select direct work, OMP internal delegation, or multi-agent delivery when the route is unclear.
  Choose independent Herdr interaction and hidden Worktrunk write isolation separately; skip clear local changes.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Route a Development Request

The parent decides the goal, scope, acceptance criteria, and verification before dispatch. This
skill does not implement code or approve a design. A clear local change needs no routing ceremony.

## Make three independent decisions

1. **Execution:** direct parent work, one OMP internal child, or multiple OMP internal children.
2. **Interaction:** remain internal for same-repository work by default. Cross-repository changes
   use the target repository's Herdr workspace and owner through `agent-communication`. Also use
   Herdr for user intervention or an explicitly required independent conversation/CLI.
3. **Writes:** use the existing checkout with disjoint scopes and one integration owner when safe.
   Use a hidden Worktrunk child worktree only when separate write ownership is required.

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
Do not invent provider/model metadata for OMP or run a legacy transport admission wrapper. Keep
existing model and permission defaults; the task contract does not choose a provider, model, or
permission bypass. Do not pass conversation history, credentials, or unrelated plans.

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
2. If write isolation is needed, use `using-git-worktrees`' hidden Worktrunk route from the recorded
   committed parent base. Otherwise explicitly assign disjoint writes in the existing cwd.
3. Dispatch through OMP's actual internal tool, using its documented cwd and role interface. Read
   the live tool help if unclear; do not substitute a separate CLI or guess a cwd parameter.
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

Read the `herdr` skill and current CLI help. Use an explicitly identified existing pane/cwd or create
one owned pane with `--no-focus` from agent control. Start the required CLI with its existing
permissions/models. Send only the bounded request and absolute trusted artifact paths; record pane,
agent identity, readiness, and submitted status. Do not leave OMP to re-create its environment merely
to delegate. Launch failure or unknown prompt receipt preserves the pane and artifacts; inspect the
same resource instead of creating another or falling back to another backend.

For another repository, read `agent-communication` and resolve that repository's actual workspace
and agent identity. Reuse an appropriate idle owner or start OMP there without focus; do not use an
internal child in the parent's checkout to edit another repository. Send only the common contract
and bounded scope. Each owner verifies locally; the parent verifies cross-repository integration.

Normal GitHub PR review goes through `pr-review --no-focus [--quick] <PR>` from agent control.
A prepared review workspace executes the `pr-review` skill in its existing OMP/root pane; it does
not create another worktree, pane, or OMP session. A shell user invokes the command without
`--no-focus` when they want the new review workspace focused.

## Bounded escalation

A deterministic failure (missing dependency, invalid result, timeout, known test failure) needs an
evidence-based correction or decision, not an escalation child. For semantic uncertainty, an
available read-only reviewer/judge may assess the fixed inputs and permitted options. It cannot
change provider, permissions, ownership, scope, or the attempt budget.

Record the initial attempt and a finite repair limit before dispatch. Default to one repair attempt
for a single task; use the bounded MAD review policy for delivery. Preserve each failed attempt and
its artifacts. Do not relaunch after unknown/timeout until liveness and ownership are established.
At the limit, report unresolved evidence and the precise required decision; never retry indefinitely.
