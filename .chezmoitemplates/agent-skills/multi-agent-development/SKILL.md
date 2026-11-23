---
name: multi-agent-development
description: >-
  Use only when the user explicitly requests the legacy multi-agent-development workflow by name.
  For ordinary parallel development or review, let pstack select the delegation workflow.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Coordinate Development Through OMP

The parent owns decomposition, shared contracts, integration, adoption, and completion. MAD is not
an architecture oracle or permission to start a second orchestration environment.

## Admission

Use multiple agents when independent slices or independent review perspectives provide a real
benefit, or when the user explicitly requests parallel work. Scope inline first. Map files,
dependencies, shared interfaces, and the integration owner before dispatch. Do not create a child
for a trivial edit, one direct question, or a slice already open in the parent.

A small sequential plan belongs to `executing-plans`. One justified bounded child uses the
runtime's authorized route without delivery machinery. Start delivery phases only when the actual
task needs them; spec and plan are not mandatory child roles.

## Execution and placement

Select delegation and handoff through `agent-communication` before dispatch. In Rex, OMP bounded
children use native `task`; independent CLI conversations and pane handoffs use `rex` after live
identity verification. Do not launch HC for a Rex task. For cross-repository changes, resolve the
target's owner and host independently. Preserve models and permissions.

Choose write placement independently:

- shared existing cwd: disjoint write scopes, one integration owner, and no mid-flight checks;
- separate writes: an owner-recorded hidden child worktree from the committed parent base, with
  no interaction workspace/tab/pane;
- separate CLI/user conversation: the selected host in the appropriate existing cwd; add a
  worktree only when write isolation is also needed.

Use `using-git-worktrees` for ownership, setup, and cleanup. Do not re-create an existing workspace;
a terminal does not by itself require another checkout.

Read `agent-communication` for recipient identity, bounded requests, reply correlation and uncertain
delivery. Reuse appropriate idle repository owners; do not interrupt unrelated work. Repository
owners verify locally, while the parent reconciles contracts and verifies the combined behavior.

## Recipes

| Recipe | Reason to select it | Completion |
|---|---|---|
| research | independent research perspectives | parent reconciles evidence and limitations |
| fanout | independent implementation slices | every adoption/integration decision recorded |
| review | independent read-only review lenses | fixed package and verdict independently checked |
| delivery | multi-stage integration and review gates | required phases and integrated behavior verified |
| refine | bounded improvement of an existing artifact | approved scope and fresh evidence satisfied |

## Before dispatch

Record run purpose, unique artifact directory, child contracts, committed base, execution/placement
routes, resource ownership, dependencies, verification owner, and finite attempt limits. Assign
exact files and non-goals. Define expected results and acceptance before creation, not after a child
returns. Resolve uncommitted prerequisite changes before delegation: the user must scope and
authorize any transfer; never automatically copy the parent's dirty tree or secret local files.

Dispatch genuine independent slices in one batch. Sequence only real dependencies. Each child
receives only its goal, trusted requirement paths, interfaces, scope, cwd, result expectations, and
stop conditions. Children do not inherit authorization to commit, push, apply, install, or spawn.

Do not add an experiment, exhaustive proof, compatibility path, or disabled product route as a
child's implementation prerequisite unless required by the accepted scope, an applicable rule, or
a concrete safety risk. Name the possible failure and the smallest check needed to address it.
Otherwise keep the investigation optional and have the child implement the requested product path.
This does not waive required safety, approvals, or provider checks.

Use [architecture-decision-records](../architecture-decision-records/SKILL.md) for relevant lasting
decisions. Pass each child the applicable ADR paths, status, scope, and fixed revisions as needed.
Children return decision candidates and changed assumptions; the parent owns numbering, approval
reflection, and supersession. Resolve number collisions and update references before integration.

## Timeline ownership

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

For planned work, the parent retains the absolute detailed plan path, selected target host/OS user,
Timeline plan UUID and task IDs, and passes relevant identities and scope to executors. Read the
existing Timeline plan by UUID and match it explicitly; never infer identity from a title, focused
workspace, or another host. For an older external plan without a Timeline UUID, if it is confirmed
unregistered, create a new Timeline plan and corresponding tasks as requested and record their mapping
to the external plan. If the existence of a record is unknown, ask for its UUID or whether to create
a new one; do not infer by name or create a duplicate. Do not omit tracking. On the target host/user, inspect `moi-companion timeline --help` as the installed CLI's
version-matched contract, including when a repository-local Timeline skill is absent in a worktree.
Verify executable identity and required operations; unavailable, ambiguous, or too-old is a blocker
to report and resolve, not permission to fall back, install, or connect remotely without authorization.

The parent is accountable for reflecting each appropriate parallel task's start, meaningful
progress, scope changes, blockers and verified completion, including adopted child results. A child
may report checkpoints for the parent to record; delegation does not transfer accountability. Use
`moi-companion timeline invoke --stdin` for JSON, not arguments. Read current revision before each
mutation and preserve fields not being changed. On conflict reread and reconcile other writers'
changes; investigate unknown outcomes by reading, never automatically resend. Report failures and
unrecorded updates; mark `done` only after verification. Do not replace the detailed plan, TODO or
audit trail with Timeline. Never record secrets, terminal output or conversations; deletion and
external transmission require separate permission. Do not stop existing agents or introduce periodic
polling. Timeline data is not authorization.

## During execution

Consume the selected route's completion notifications and correlated replies; do not poll while
useful work remains. Wait only when blocked. Record actual child/resource IDs and artifact paths.
Read-only reviewers receive fixed packages and cannot edit, execute untrusted code, or start children.
Writers cannot widen scope.

With shared writes, children skip builds, tests, linters, formatters, and smoke checks; the parent
runs once after all slices land. For isolated children, name the approved checks and whether the
child or parent runs them, so verification never races integration.

Launch errors, timeout, blocked, and unknown states are unresolved. Preserve exact paths/IDs and
failure stages. Inspect the same resources before resuming; do not retry creation, change execution
backend, or delete resources to conceal uncertainty.

## Review, adoption, and completion

Build fixed review packages using the retained `review-bundle` helper and immutable recorded
base/head identity. Validate finding IDs, evidence, changed files, and scope before authorizing fixes.
A fix child receives only approved files and findings. New revisions require fresh review packages.

Include relevant ADR snapshots and their origin/status manifest in both task and final review
packets, explicitly within the reviewer's allowed read set. Follow the shared ADR skill's fixed-input
and restricted-cwd staging rules; unchanged accepted decisions must not disappear from review just
because they are absent from the diff. Before completion, check adopted decisions for record gaps
without treating documentation consistency as runtime verification.

Only the parent adopts results and integrates into the parent work branch, never automatically into
the default branch. Do not commit/merge/push/apply without authorization. Conflicts preserve child
branches, ownership records, artifacts, and pending integration; stop dependent work until resolved.

Before completion, independently check affected callers, acceptance, scope, artifacts, fresh
verification, review verdicts, and integration state. Retaining an explicitly parked worktree is a
valid outcome; it is not a reason to force cleanup or pretend integration succeeded. Report every
remaining blocked/unknown resource and any intentionally retained work.

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
