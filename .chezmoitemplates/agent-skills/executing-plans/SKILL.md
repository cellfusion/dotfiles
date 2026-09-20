---
name: executing-plans
description: >-
  Use when executing small implementation plans that do not require MAD serially within
  this session. Plans with parallelizable tasks or requiring worktree isolation are better
  suited for multi-agent-development. Consumes tasks sequentially, reviewing diffs at task boundaries.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Executing Plans Serially

## Overview

Read the plan, review it critically, execute all tasks, and report completion.

**Announce at start**: "Implementing this plan using executing-plans."

**Check first**: Is this plan small enough not to require MAD? If any of the following apply, `multi-agent-development` is more appropriate:

- Two or more tasks have no dependencies and can run in parallel
- Tasks write simultaneously, requiring worktree isolation
- Independent reviewer gates are desired for each task

If none apply, execute sequentially using this skill. Do not spawn child agents. The parent implements directly and reviews diffs at task boundaries.

## Steps

### Step 1: Read and Review Plan

1. Prepare isolated workspace (using-git-worktrees)
2. Read plan file
3. Review critically. Identify ambiguities or concerns
4. If concerns exist, raise them with the user before starting
5. Otherwise, create todos per task and proceed

### Step 2: Execute Tasks

For each task:

1. Mark todo as `in_progress`
2. Follow each step as written (plans are divided into bite-sized steps)
3. Run specified verifications
4. Mark todo as completed

At each task boundary, inspect that task's diff. Verify spec compliance (omissions, extras, misunderstandings) and test effectiveness. This replaces the review recipe from multi-agent-development.

### Step 3: Finish Development

Once all tasks are completed and verified:

- Announce: "Completing this work using finishing-a-development-branch."
- Launch `finishing-a-development-branch`, running through test verification, presenting options, and executing the chosen action.

## When to Stop and Ask

**Halt execution immediately when**:

- Hitting blockers (missing dependencies, broken tests, unclear instructions)
- Plan has critical gaps preventing commencement
- Meaning of instructions is unclear
- Verifications fail repeatedly

**Confirm rather than guess.**

## When to Return to Prior Steps

**Return to Step 1 review when**:

- Plan is updated in response to user feedback
- Fundamental approach needs reconsideration

**Never brute-force through blockers.** Stop and ask.

## Key Takeaways

- Review plan critically first
- Follow plan steps as written
- Do not skip verifications
- Stop when stuck; never speculate
- Never begin implementation on main / master without explicit user approval
- If implementation proves larger than anticipated, stop and ask user whether to switch to multi-agent-development
