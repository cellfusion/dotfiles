---
name: multi-agent-development
description: >-
  Coordinate multiple OMP internal children or independent reviews with bounded scopes and artifacts.
  Use Herdr only for independent CLI interaction and Worktrunk only for hidden write isolation.
  Skip a single local task or a small sequential plan.
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

A small sequential plan belongs to `executing-plans`. One justified bounded child uses the ordinary
OMP internal tool without delivery machinery. Start delivery phases only when the actual task needs
them; spec and plan are not mandatory child roles.

## Execution and placement

Default to OMP internal delegation for same-repository work, using the current runtime's documented
task/agent interface. For cross-repository changes, use each target repository's Herdr workspace
and owner through `agent-communication`, not internal children editing foreign checkouts.
Preserve existing model and permission defaults. Do not use provider snapshots or
transport-specific request schemas to authorize an OMP child.

Choose write placement independently:

- shared existing cwd: disjoint write scopes, one integration owner, and no mid-flight checks;
- separate writes: a hidden Worktrunk child worktree from the committed parent base, with no Herdr
  workspace/tab/pane;
- separate CLI/user conversation: Herdr pane in the appropriate existing cwd; add a worktree only
  when write isolation is also needed.

Use `using-git-worktrees` for ownership, setup, and cleanup. Do not re-create an existing workspace
or start a second orchestration runtime for ordinary delegation.

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

## During execution

Consume actual runtime completion notifications; do not poll while useful work remains. Wait only
when blocked. Record actual child/resource IDs and artifact paths. Read-only reviewers receive fixed
packages and cannot edit, execute untrusted code, or start children. Writers cannot widen scope.

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

Only the parent adopts results and integrates into the parent work branch, never automatically into
the default branch. Do not commit/merge/push/apply without authorization. Conflicts preserve child
branches, ownership records, artifacts, and pending integration; stop dependent work until resolved.

Before completion, independently check affected callers, acceptance, scope, artifacts, fresh
verification, review verdicts, and integration state. Retaining an explicitly parked worktree is a
valid outcome; it is not a reason to force cleanup or pretend integration succeeded. Report every
remaining blocked/unknown resource and any intentionally retained work.

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
