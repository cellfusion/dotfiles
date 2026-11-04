# Worktree lifecycle ownership

- Status: Accepted
- Date: 2026-10-28
- Approval: User approved the unified lifecycle and selected primary-checkout copying, private machine-local project configuration, and setup for review and agent child checkouts.

## Context

Lazygit, Worktrunk and Herdr's native worktree creator used different creation and removal paths. This made checkout locations and initialization inconsistent. Project-specific setup must not require files committed to the repository. Existing checkouts and their ownership must remain intact.

## Decision

Worktrunk owns new checkouts created by the configured UI routes and agent child / Herdr PR-review flows. Herdr opens the resulting path without taking checkout ownership. Existing checkouts are not migrated. The configured Herdr keyboard and mobile entries use this path; Herdr's native sidebar and direct `herdr worktree create` are outside it because their backend cannot be overridden by configuration. Orca review continues to use Orca-owned worktrees and its existing setup policy; the user does not currently use that route.

The Worktrunk user configuration retains machine-local per-project settings outside the managed section. New worktrees copy only ignored files selected by `.worktreeinclude` in the primary checkout before project setup. When the include file is absent nothing is copied. This includes review and child checkouts; entries may include secrets and should be selected deliberately. Personal commands are trusted by virtue of local configuration. Project-supplied commands require explicit Worktrunk approval. Unresolved approval blocks managed create and remove paths; never pass `--yes` to bypass it.

Worktree removal defaults to retaining the branch and not forcing removal. Workspace/pane ownership remains distinct from checkout ownership. Failed or active work remains in place for inspection.

## Alternatives and consequences

- Independent Herdr/Git worktree creation does not run Worktrunk's lifecycle; keeping it as the primary path would retain inconsistent setup.
- A committed project file can share settings, but cannot replace machine-private per-project configuration; both can be used when explicitly appropriate.
- Suppressing all hooks in review and child checkouts would avoid copying credentials and running setup but contradicts the chosen common lifecycle. This decision makes those privacy and execution risks explicit and retains approval checks.
- Existing locations and the Orca route are retained rather than silently moved or relabelled. Revisit the Orca exception if its supported API can adopt an existing checkout and the route is needed.
