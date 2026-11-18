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

Consult [architecture-decision-records](../architecture-decision-records/SKILL.md) for relevant
project decisions. Include their project-relative paths, status, and applicable scope in the plan
and handoff. Do not treat Proposed records as approved constraints. If planning exposes a new
significant unresolved choice, return it to design rather than inventing approval. ADRs preserve
lasting rationale inside the project; this does not change the external plan destination or turn
a planning-only request into permission to create project files.

## Timeline registration

For a new plan, the default agent execution host is the host running the agent process; use the
Timeline store of `moi-companion` running on that host as the same effective OS user as the agent process.
This remains true when controlled from a remote UI client. Do not infer the store from the client
host, repository name, or workspace focus; normally no confirmation question is needed for this default.
If the user explicitly requests another host, confirm that target, its connection and authorization
before using it; never substitute the current host. If the host cannot be identified, report the
blocker and ask how to proceed; do not guess a host, user, executable, or store.

For an existing plan, preserve the existing plan identity and its recorded or handed-off host/user,
UUID and task IDs even if they differ from the new agent's default. Do not connect to another host
without authorization; do not create a replacement plan in the current host's store. Coordinate a
safe update method with the parent or user, respecting the recorded target; report unrecorded updates
until that method is available.

Before any Timeline mutation, distinguish these cases:

- If the user specifies an existing plan, or a trusted record or parent handoff clearly identifies one,
  retain its UUID and host/user, read and match that plan, and confirm the intended task mapping;
  do not automatically append tasks.
- If no existing plan is intended and no applicable record exists, create a new Timeline plan with a
  fresh UUID and register its hierarchical tasks in the selected host and OS user's store. For a new
  plan, do not guess a link to an old record.
- If record existence is unknown, ask for its UUID or whether to create a new one before mutation;
  do not infer by name or create a duplicate.

Do not contact another host without authorization. Keep the detailed external plan file as the
implementation guide; Timeline is the shared progress record, not a
replacement for the plan, TODO, or audit trail. Preserve an explicit TODO origin when known;
otherwise use `origin: null`.

On that same host/user, inspect `moi-companion timeline --help` as the installed CLI's primary
contract: newer companions embed their version-matched Timeline instructions even when a
repository-local skill is absent in another worktree. Verify the executable identity and required
operations; an unavailable, ambiguous, or too-old command is not permission to use a namesake or
fallback store. Report the blocker and ask how to proceed; do not silently omit tracking or install
software. Use `moi-companion timeline invoke --stdin` for JSON requests, not command arguments.
For a new plan, generate fresh task UUIDs and add tasks with parent IDs and current revision as
directed by that help. Never choose an existing plan by title or focus. On conflict reread and reconcile; for an unknown mutation result reread
and investigate, never automatically resend. Do not record secrets, terminal output, or conversations.
Deletion and external transmission require separate authorization; do not stop existing agents or
introduce periodic polling to track the plan.

Record meaningful starts, progress, scope changes, blockers, and verified completion during planning
and subsequent work. If tracking fails, report what is unrecorded and resolve it rather than claiming
success. Hand off the absolute plan path, target host/user, Timeline plan UUID and task IDs to the
next executor; retain these identities without copying sensitive content. Registration does not grant
permission to implement the plan or perform destructive or external actions.

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

### Organize work around outcomes

Group substantial work by the observable deliverable or capability it produces, rather than only by
activity labels such as research, implementation, or testing. Give each outcome a short concrete
title and split it into checkable actions. For each action identify its relevant target, prerequisite,
expected result and a practical way to verify it. A shared check may verify multiple actions when
its evidence covers each; do not require a separate test run for every line. Include failure paths,
integration and evidence where they matter; do not claim that a test, mock, prototype or report is
the requested product.
Order actions by real dependencies and state which independent actions can proceed in parallel.

Keep confirmed requirements, proposed approaches and unresolved decisions distinct. If a decision
is missing, write a bounded decision or investigation action with its required input and observable
output; do not fabricate the decision or imply that implementation is approved. Preserve scope and
safety boundaries. Do not force an outcome hierarchy, numerical weights or a fixed template where a
simple sequence is clearer.

For plans intended to guide ongoing work, specify how the owner will record meaningful checkpoints:
what changed, verification evidence or a blocker, its effect on the outcome and remaining work.
When scope changes, revise the existing item and retain completed evidence rather than silently
rewriting history. When delegating, give the child the relevant outcome, task identifiers where
available, boundaries and completion criteria; the owner integrates and verifies the reported result
before marking the work done. These are planning instructions, not permission to start work, replace
an existing TODO system, send messages, or invent an always-on tracking service.

## Authoring

The parent may write the plan directly. Delegate plan writing only when independent research,
long-running decomposition, or a separate perspective is worth the cost. If a child writes it,
provide only purpose, approved specification path, known constraints, and destination. The parent
reviews and adopts the result; a child cannot make hidden design decisions.

## Review the plan

### Check whether a reader can act on it

Put the purpose, confirmed requirements, proposals, open decisions and next permitted action where
an implementer can find them. Distinguish research about another system from the planned product.
Give each implementation step its dependencies, affected components, outcome and verification;
state how optional or unselected steps affect later gates. Preserve uncertainty rather than making
an unresolved behavior or approval look decided. Use lists, tables or a diagram when they clarify
relationships; they do not replace the explanatory text.

For a consequential or hard-to-follow plan, or when the user asks, freeze the exact draft and ask
an independent reader to reconstruct the goal, confirmed versus undecided items, next permitted
action, task order, acceptance checks and stop conditions from that draft. Do not provide the
expected answers in the comprehension prompt. Compare the reconstruction with the user's actual
request and the draft, verify findings, and correct material misunderstandings or contradictions.
After material changes, freeze the revised draft and recheck affected passages with the same
reviewer or a new reader as appropriate. If independent review is unavailable, report that
limitation; do not claim the plan was independently understood. This check does not replace design, security or technical review.
Use proportionate review: do not require agents for a clear small plan.

Before presenting it:

1. read it from disk
2. validate task numbering and dependencies
3. inspect file overlap within parallel waves
4. check acceptance criteria and verification commands
5. confirm the plan produces a working, testable result
6. record rejected findings and reasons

Use an existing dependency validator when available. Do not silently discard validator findings.
Reject them with rationale, preserve them as an unresolved constraint, or ask the user.

If planning introduces a consequential design decision that was not already reviewed, use
`design-checkpoint-review` on that decision before presenting the plan or starting implementation.
Do not repeat a checkpoint for an unchanged, already reviewed design.

## Approval and preview

Show the plan at its external absolute path. Obtain user approval when consequential choices remain
unresolved or an external or destructive action requires authorization. A public contract or worktree
delegation does not by itself require approval again when the user already decided it. Do not add a
formal approval gate merely to restate a clear user request.

If a preview editor is used, re-read the plan after the user responds. The on-disk version is
canonical. Incorporate manual edits before handing the plan to `executing-plans` or
`multi-agent-development`.

Never run an implementation or cleanup command while waiting for approval.

## Handoff

Choose execution based on plan structure:

- sequential small plan with no parallelism: `executing-plans`
- independent tasks, isolation, or task/final review gates: `multi-agent-development`

Re-read the approved plan immediately before handoff. Pass its absolute path, not copied prose,
along with the Timeline host/user, plan UUID and relevant task IDs.

For justified OMP delegation use HC through `agent-communication`; other runtimes retain their
native internal route. If HC is unavailable or conflicts with higher-priority runtime policy,
report the blocker without silently falling back to OMP `task`. State execution and write
placement independently in the handoff: reuse the approved checkout; use hidden Worktrunk only for
separate writer ownership, with no extra pane. An independent CLI conversation uses the selected
supported host: herdr-core can run a hidden terminal without a
legacy workspace; legacy Herdr remains supported. Only use herdr-app for visible UI the user
requested. Record the committed base and prerequisite decisions; do not automatically copy
uncommitted parent changes or grant commit/push/apply permissions. Name the integration/verification
owner for shared writes.

## Completion

A plan is complete when it is saved, self-reviewed, validated, and either approved for execution or
explicitly retained without execution. Report the path, validation evidence, unresolved decisions,
and selected downstream skill.
