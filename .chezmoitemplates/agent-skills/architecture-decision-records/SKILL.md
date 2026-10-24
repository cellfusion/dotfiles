---
name: architecture-decision-records
description: >-
  Create, consult, and supersede project-local architecture decision records for significant,
  lasting design choices. Use when design, implementation, or review needs a decision's rationale;
  do not require an ADR for routine local changes or copy entire plans into the repository.
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}
{{ includeTemplate "agent-skills/_audit.md" . }}

# Preserve Architectural Decisions in the Project

Keep one short record per significant decision, so a later session can understand the choice without
private conversation history or external working artifacts. ADRs record why, not task progress.
This skill grants no permission to commit, push, apply configuration, or widen the requested scope.

## Consult before deciding

Read the supplied project rules and existing documentation entry points. Reuse the project's ADR
location, naming, language, template, and approval rules. Discover relevant records by title and scope,
then read those records and follow supersession links; do not load the whole decision log every time.
An Accepted ADR applies only within its stated scope. Proposed and Rejected records are not accepted
constraints. Do not treat the newest filename or current code as proof that a decision was approved.

If no convention exists, use `docs/adr/NNNN-short-title.md` inside the target project. Use increasing
numbers and never reuse a published number. Do not migrate existing records or add a second directory
beside an established one. Ask only if conflicting conventions leave the destination ambiguous.
If project rules prohibit the write or permissions prevent it, report the limitation; an external
copy is not successful project-local persistence.

## Decide whether a record is needed

Record lasting decisions whose rationale will matter to future changes, including:

- persistent data models, public contracts, compatibility, or security/permission boundaries;
- major dependencies, component boundaries, deployment or execution models;
- consequential performance, consistency, availability, or operational tradeoffs;
- changes to an existing accepted decision.

Do not create ADRs merely for a large diff, a routine dependency bump, an existing-design bug fix,
mechanical edits, temporary task ordering, or session setup. If no significant decision exists,
continue the normal lightweight workflow without a new approval gate or an empty ADR.

A research-only or planning-only request does not itself authorize project writes. Consult existing
records and report candidates in the requested external artifact unless a project-local draft was
requested. Plans, specifications, research originals, review evidence, and audit logs keep their own
storage contracts; do not move or copy them wholesale into ADRs.

## Write a self-contained draft

Use the existing project format, or [the minimal template](references/adr-template.md) when none exists.
Include title, status, date, context and constraints, decision with rationale, options actually
considered, and positive and negative consequences. Include reconsideration conditions and relative
links to predecessor/successor records when applicable. State unknown historical reasons as unknown;
never invent rejected alternatives or reverse-engineer author intent from code.

Start an undecided proposal as Proposed. Write enough context to understand it without access to
external specs, plans, sessions, or local absolute paths. Link project files relatively and use
accessible issues, PRs, or primary sources for supporting detail. Do not copy raw conversation,
credentials, personal information, private review logs, or machine-local artifact paths.

## Reflect real decisions, not implementation progress

Follow the project's actual decision authority and existing status vocabulary; never mass-convert
custom statuses. With the default vocabulary:

- **Proposed:** under consideration, including a paused or unfinished proposal.
- **Accepted:** approved within the project's authority. Record decision date and a safe, attributable
  approval basis (for example, an approved design or explicit user choice). Existing approval of the
  same decision is sufficient; do not ask for duplicate approval. Implementation completion or a
  child's recommendation alone is not approval. Respect explicitly delegated decision authority.
- **Rejected:** formally declined; retain the proposal and rejection reason. Considered alternatives
  do not each need separate rejected files.
- **Superseded:** a previously accepted decision replaced by an accepted successor.

Accepted does not mean implemented, merged, or verified. Preserve accepted/rejected decision content
as history. Correct typos or broken links only when meaning is unchanged. For a different decision,
create a new Proposed ADR and keep the old Accepted decision effective until its successor is
accepted. Then mark the predecessor Superseded and link both directions in the same scoped update.
A rejected replacement does not invalidate the old decision. If code conflicts with an ADR, determine
whether the code is defective or the decision needs changing; do not silently rewrite the rationale.

## Ownership and handoff

The parent owns numbering, recording approval, and supersession. Children receive the relevant ADR
paths, status, scope, and fixed revisions where needed; they return decision candidates or changed
assumptions rather than independently allocating numbers or approving decisions. Resolve numbering
collisions before integration and update references. Do not add a numbering service or lock system.

At design/plan handoff, name relevant ADRs, their status and applicable scope. At completion, check
that significant adopted decisions are recorded, links and status agree, and unresolved proposals
are reported. Do not use ADR consistency as proof that the product works.

For bounded code review, include the relevant ADRs even when unchanged by the diff. Save immutable
snapshots beside the external review package with a manifest mapping each snapshot to its project
path, base/head commit (or explicitly uncommitted input), status, and content identity. Include old
and proposed replacement records where applicable. Explicitly authorize those snapshot paths in the
reviewer's read set; Proposed text never overrides Accepted constraints just by appearing at head.
If cwd restrictions require staging, copy the snapshots and manifest along with the package and
requirements, and adjust authorized paths without losing origin identity or supersession context.
Review copies do not replace the project-local originals and never prove an uncommitted ADR was in
the reviewed commit.
