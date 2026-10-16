# Herdr Interaction and Checkout Ownership

For new manual operations, read the installed `herdr` skill and selected CLI's current help.
Require a verified current Herdr session; outside Herdr do not inspect/control a focused session.
Prepared review uses this run-local reference and runtime validation, not global skill discovery.
Explicit `--environment herdr` does not authorize operation outside the host.

## PR review adapter

Use `pr-review --environment herdr --no-focus [--repo-path /absolute/repository] [--quick] <PR>`.
The default repository is cwd; a URL must match that repository. `--project` is Orca-only.
The entry verifies capabilities before side effects, creates the base-SHA checkout with Worktrunk
hook suppression, then attaches a no-focus Herdr workspace with its dedicated root pane. This is
not a Herdr-owned worktree: record `checkout.owner=worktrunk` and the created branch as `ownerId`.
Do not substitute `herdr worktree create` merely because it is available; its setup/hook suppression
must be established before using that route. Do not reuse a user's existing pane for the reviewer.

The root pane launches OMP with a run-private session directory, `autoResume: false` overlay and
`umask 077` before exec. Preserve existing models and permissions. Readiness requires actual live
agent/pane identity, not a workspace label or idle shell. Send one explicit bounded skill-read
request, not a startup slash command. Inspect the same agent after timeout/unknown receipt; never
resend or start a replacement automatically.

The v3 interaction identity is `sessionSocket`, `workspaceId`, `tabId`, `paneId`, `terminalId`,
`agentName`, `agentKind: "omp"`, and `agentSession: {agent, kind, source, value}`. These are returned
and live-verified identities, not names guessed from UI order. The adapter inspects the actual host
and matches exact checkout cwd, session, workspace, pane, terminal and agent session. Do not inject
recorded launch values as live evidence. Herdr prompt acceptance is acceptance only; never fabricate
Orca's `turn_started` or claim a completed review from agent idle state.

## Manual interaction and inspection

Use `herdr workspace list`, `herdr pane list --workspace <actual-id>`, `herdr pane process-info`
and `herdr agent get <actual-name>` according to current help. Resolve actual cwd and foreground
process/agent session; labels are hints only. For a bounded independent conversation, reuse an
appropriate verified idle owner or start a dedicated agent in an approved pane without focus.
Read `agent-communication` for a new communication task; that does not authorize a new checkout.

For a separately approved Herdr-owned visible worktree, inspect live help and hook/trust policy
before creation. Require safe setup suppression; if unavailable stop rather than silently execute
hooks. Use an explicit recorded workspace, immutable base and `--no-focus`, and accept only returned
workspace/root-pane/path values. Verify path, branch, common Git directory and base before handoff.
If the safe route instead creates a Worktrunk checkout and attaches a workspace, keep both owners
separate; do not label the checkout Herdr-owned.

## Cleanup

After explicit cleanup approval and proven saved/inactive state, a **Herdr-owned** worktree uses
`herdr worktree remove --workspace <recorded-id>` without force, matching the exact recorded path.
An attached workspace over a Worktrunk checkout is a separate resource: verify its ownership and
use current workspace-removal help, then the Worktrunk owner route for the checkout. Do not use
Herdr worktree removal on another owner's checkout. Retain unknown, running, failed or dirty
resources and all review artifacts; review posting never triggers removal.
