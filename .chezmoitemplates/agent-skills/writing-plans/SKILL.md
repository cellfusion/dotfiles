---
name: writing-plans
description: >-
  Use to turn multi-phase work with finalized specs or requirements into an implementation
  plan before touching code. Launch only when plans are required for multi-phase implementations
  (such as after architectural design has solidified). Write plan to destination returned by
  agent-docs-dir plans and hand off to downstream skills according to execution strategy.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# Writing Implementation Plans

## Overview

A plan may be authored directly by the parent, or delegated to a child when appropriate. For small plans, the parent reads target code and defines tasks, dependencies, and verification methods directly. Spawn `plan-author` or review children only when extensive research, independent task breakdown, or separate perspective reviews are warranted.

The parent is responsible for the plan's purpose, premises, and adoption decisions. Utilizing children is a means to improve quality, not a prerequisite for plan authoring.

Criteria for what plans should be are held in `_criteria-plan.md` and required validators.

**Destination**: `YYYY-MM-DD-<feature-name>.md` in the directory returned by `~/.agents/skills/_shared/scripts/agent-docs-dir plans` (prefer project-specific CLAUDE.md directives if present).

**Before starting**, run `~/.agents/skills/_shared/scripts/agent-docs-dir plans`. It ensures the directory exists and returns the absolute path on one line. The directory is `~/docs/<owner>/<repo>/plans/`.

The destination resides outside the repository working tree. Because it resolves to the exact same absolute path whether called from the main checkout or a worktree, pass absolute paths to downstream skills.

## Scope Confirmation

If a spec spans multiple independent subsystems, it should ideally have been divided during brainstorming. If not, propose splitting into separate plans per subsystem. Each plan must produce working, testable software on its own.

## Authoring the Plan

Execute `~/.agents/skills/_shared/scripts/agent-docs-dir plans` to determine the destination path. Whether written directly by the parent or delegated to a child, pass the absolute path of the plan downstream.

When delegating to a child, pass only the objective, approved spec's absolute path, known constraints, and plan destination. If the child raises questions, the parent reviews the content before forwarding to the user. The parent must not conceal choices or allow the child to make unilateral determinations.

## Reviewing the Plan

The parent reads the plan, verifying task dependencies, modified files, verification methods, and feasibility. Add `plan-author` or `reviewer` only if the plan is large, contains numerous independent tasks, or requires distinct perspectives.

Verify task numbers, dependencies, and same-wave file conflicts using existing validators such as `paseo-plan-dependency-validate`. The parent decides whether to adopt validator recommendations. Correct the plan after consulting the user only if severe ambiguity or defects blocking implementation remain.

If consequential ambiguities or defects remain, the parent selects one of:
- Reject the finding with rationale
- Leave as an unresolved constraint in the plan to guide implementation
- Confirm with the user and adjust the plan

Never silently drop findings.

{{ includeTemplate "agent-skills/_preview-tab.md" . }}

{{ includeTemplate "agent-skills/_approval-gate.md" (merge (dict "artifact" "plan" "nextLabel" "implementation" "issue" false "worktree" true) .) }}

Plans are not converted into GitHub issues. Implementing agents (`multi-agent-development` / `executing-plans`) directly read the plan file path; without the file, execution mechanisms cannot function.

{{ includeTemplate "agent-skills/_worktree-handoff.md" . }}

## Handoff to Implementation

Once approved, choose the execution method based on plan size and structure, not whether subagents are available:

- **Plans with parallel tasks or requiring worktree isolation** -> Pass to `multi-agent-development`. Spawns Paseo children per task with review recipes interleaved.
- **Small plans that do not require MAD** -> Pass to `executing-plans`. Runs sequentially within this session, reviewing at task boundaries.

When deciding between the two, evaluate task dependencies, file conflict likelihood, and review requirements. If parallelism and isolation are unnecessary, use `executing-plans`.

Use MAD's strict contracts and worktree isolation only when choosing `multi-agent-development`.

## Notes

- If the parent can assess plan content directly, do not add child reviews.
- Validate task dependencies and file conflicts with existing validators where available.
- Present options with impacts to the user only when their choice is necessary.
- Re-read the plan to incorporate manual edits and environment diffs before handing off.
