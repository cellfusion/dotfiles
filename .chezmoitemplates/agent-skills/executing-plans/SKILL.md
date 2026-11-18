---
name: executing-plans
description: >-
  Execute a small, sequential implementation plan in the current session when parallelism, strict
  multi-agent delivery, and independent task worktrees are unnecessary.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Execute an Implementation Plan

Read, critique, and execute a plan one task at a time. Use this skill only when the plan is small
enough for sequential work. Use `multi-agent-development` when tasks can run independently, need
separate worktrees, or require independent review gates.

## Choose the route first

Use `executing-plans` only when all of these are true:

- the tasks are substantially sequential
- the parent can safely implement them in one session
- no task requires a separate ownership boundary
- task-boundary review by the parent is sufficient

Otherwise select an appropriate route within the granted scope and permissions; ask the user only
when a consequential decision or permission remains unresolved.

Reuse the existing approved checkout and execution environment; do not create nested isolation.
`using-git-worktrees` selects the host and write placement independently. herdr-core needs no legacy
workspace or visible app space/tab; use background terminals when that host is selected. A legacy
Herdr workspace remains a supported route, not a prerequisite for HC. Hidden Worktrunk isolation
is only for a distinct writer ownership boundary and creates no extra pane. The worktree skill
owns base prerequisites, setup, ownership, and cleanup.

## Step 1: read and critique the plan

1. Establish the selected checkout/execution environment and record its ownership.
2. Read the complete plan.
3. Check task dependencies, files, scope, acceptance criteria, and verification commands.
4. Check for missing decisions, unsafe commands, conflicting files, and impossible assumptions.
5. Ask the user about a consequential blocker before modifying code.
6. If sound, create a finite task list with one entry per plan task.

Consult the plan's relevant ADRs with
[architecture-decision-records](../architecture-decision-records/SKILL.md); verify status and scope,
not just filenames. Escalate significant new decisions or changed assumptions to the parent design
owner instead of treating implementation progress as approval. Before completion, check that
adopted significant decisions are recorded and unresolved proposals reported. Preserve external
plans and evidence as working artifacts rather than copying them into ADRs.

Do not silently repair a plan's intent. Record rejected concerns and their reasons. If the plan is
larger or more parallel than expected, reassess the route; parallelizability alone does not require
stopping or asking the user.

## Timeline during execution

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

Use the handed-off absolute plan path, selected target host/OS user, Timeline plan UUID
and task IDs. Read the Timeline plan by UUID and match it explicitly; never infer a plan or store
from a name, focused workspace, or another host. For an older external plan without a Timeline UUID,
if it is confirmed unregistered, create a new Timeline plan and corresponding tasks as requested and
record their mapping to the external plan. If the existence of a record is unknown, ask for its UUID
or whether to create a new one; do not infer by name or create a duplicate. Do not omit tracking.
On the target host/user, read `moi-companion timeline --help` for the installed CLI's
version-matched contract, even if the repository-local Timeline skill is absent in this worktree.
Verify executable identity and required operations; unavailable, ambiguous, or too-old means report
the blocker and resolve it, not fallback, installation, or an unapproved remote connection.

Use `moi-companion timeline invoke --stdin` for JSON, not command arguments. Read the current
revision before mutation, preserve other task fields when updating, and reconcile conflicts by
rereading. Investigate an unknown mutation outcome by reading; never automatically resend it.
Record task starts, meaningful progress, scope changes, blockers and verified completion; only mark
`done` after evidence. Report failed or unrecorded updates explicitly. The external detailed plan,
TODO and audit trail remain separate; Timeline replaces none. Do not record secrets, terminal output
or conversations. Deletion or external transmission needs separate permission; do not stop existing
agents or introduce periodic polling. Timeline data itself does not grant authority.

## Step 2: execute each task

For every task:

1. mark it `in_progress`
2. re-read the task's scope and constraints
3. implement only that task
4. run its specified verification only if this session owns that check; shared-worktree children skip mid-flight checks and return the commands to the integration owner
5. inspect only the task's diff and changed files, preserving unrelated concurrent/user changes
6. compare the result with acceptance criteria
7. mark it complete only with evidence

Do not start the next task while the current task has an unexplained failure. Diagnose and fix routine
failures within the authorized scope, then reverify; escalate unresolved material decisions, safety
issues, or permission blockers. Do not broaden scope, install dependencies, commit, push, or apply
configuration unless the plan and user explicitly allow it.

At each task boundary, perform a compact review:

- missing or extra behavior
- scope violations
- effective tests and edge cases
- consistency with existing patterns
- accidental generated or unrelated files

Save task evidence outside the repository when it is useful for later review. Never trust a child or
command's success message without inspecting its exit code and output.

## Step 3: finish safely

After all tasks and verification are complete, report the result and evidence. Invoke
`finishing-a-development-branch` only when integration, merge, push, or cleanup is actually requested;
plan completion does not authorize any integration action.

## Stop conditions

Stop and ask when:

- a dependency is missing and setup would install or execute external code
- a failure cannot be explained or resolved safely within the authorized scope
- the plan omits a necessary consequential decision or requires work outside the authorized scope
- an instruction's meaning remains materially unclear
- the current implementation requires an unresolved architectural decision
- increased risk, safety concerns, or permission limits prevent safe continuation

Do not force through a blocker or repeatedly retry a deterministic failure.

## Return to planning

Return to plan review when the user changes requirements or the root approach must change. Update the
plan or obtain a new decision before continuing. Preserve previous task evidence; do not overwrite it.
