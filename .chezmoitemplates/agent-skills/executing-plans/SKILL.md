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

Otherwise stop and select MAD or ask the user.

Write changes in an isolated workspace by default using `using-git-worktrees`. Stay in the current
checkout only when the user explicitly accepts that risk and the change is safe to make there. The
worktree skill owns setup, baseline policy, ownership, and cleanup; do not duplicate or bypass it.

## Step 1: read and critique the plan

1. Establish the selected workspace and record its ownership.
2. Read the complete plan.
3. Check task dependencies, files, scope, acceptance criteria, and verification commands.
4. Check for missing decisions, unsafe commands, conflicting files, and impossible assumptions.
5. Ask the user about a consequential blocker before modifying code.
6. If sound, create a finite task list with one entry per plan task.

Do not silently repair a plan's intent. Record rejected concerns and their reasons. If the plan is
larger or more parallel than expected, stop and ask whether to switch to MAD.

## Step 2: execute each task

For every task:

1. mark it `in_progress`
2. re-read the task's scope and constraints
3. implement only that task
4. run its specified verification
5. inspect the task diff, changed files, and working-tree status
6. compare the result with acceptance criteria
7. mark it complete only with evidence

Do not start the next task while the current task has an unexplained failure. Do not broaden scope,
install dependencies, commit, push, or apply configuration unless the plan and user explicitly allow
it.

At each task boundary, perform a compact review:

- missing or extra behavior
- scope violations
- effective tests and edge cases
- consistency with existing patterns
- accidental generated or unrelated files

Save task evidence outside the repository when it is useful for later review. Never trust a child or
command's success message without inspecting its exit code and output.

## Step 3: finish safely

After all tasks and verification are complete, invoke `finishing-a-development-branch`. That skill
must verify the final tree, ask how to integrate it, and wait before merge, push, commit, apply, or
cleanup. It must not assume that “plan complete” authorizes any integration action.

## Stop conditions

Stop and ask when:

- a dependency is missing and setup would install or execute external code
- a test or verification fails
- the plan omits a necessary decision or file
- the meaning of an instruction is unclear
- the current implementation requires a different architecture
- the change is larger, more parallel, or riskier than the plan permits

Do not force through a blocker or repeatedly retry a deterministic failure.

## Return to planning

Return to plan review when the user changes requirements or the root approach must change. Update the
plan or obtain a new decision before continuing. Preserve previous task evidence; do not overwrite it.
