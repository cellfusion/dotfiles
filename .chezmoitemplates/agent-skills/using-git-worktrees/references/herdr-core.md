# herdr-core Interaction and Checkout Ownership

## Manual host selection and live identity

Read the installed `herdr-core` skill and `hc --skill` before new manual operations; use
`hc <command> --help` for current arguments. Core (`hc`) is not the legacy `herdr` multiplexer.
It provides persistent terminals, not workspaces, panes, window layout or worktree ownership.
An installed binary or a terminal name does not establish the current execution host.

Inside core, require a nonempty `HC_TERMINAL_ID` and inspect that exact address with
`hc get "$HC_TERMINAL_ID" --json`. Match the returned live terminal ID, machine/address and
observed process/cwd to the recorded interaction and exact checkout path before control or
handoff. Do not inject expected IDs as live evidence. `HERDR_ENV`, app focus and labels do not
substitute for this inspection. Missing, conflicting or inaccessible identity blocks current-host
adoption; never fabricate it or operate on whichever terminal happens to be visible.

Outside core, do not claim an inherited core session. A separately requested manual launch must
use an explicit target machine and absolute cwd, record the actual returned terminal address and
verify it live. Read the core skill's communication contract before starting an external agent;
internal delegation needs no core terminal. Keep orchestration background/hidden by default.
Core has no no-focus workspace operation: do not translate legacy workspace/pane commands to it.
Visible UI belongs to the distinct `herdr-app` skill and `herdr-app --skill`; create, reveal or
rearrange app views only when the user requests visible work.

## Checkout isolation remains Worktrunk-owned

Reuse an approved existing checkout where appropriate. For new write isolation follow
[Worktrunk](worktrunk.md), recording its branch/path/base and configured lifecycle approval
independently of core. Worktrunk creates no workspace, pane or app UI. A core terminal launched
with that checkout as its explicit cwd is only an interaction resource: record
`checkout.owner=worktrunk` and its owner-specific ID separately from terminal address, parent,
creation receipt and liveness. Core visibility never transfers checkout ownership.

Before handoff verify the exact checkout's common Git directory, branch and immutable base as
well as the live terminal identity. Preserve the returned full remote address where applicable;
local file tools do not inspect a remote machine. Retain resources on failed inspection rather
than recreate, switch hosts or execute unapproved hooks.

## No automated PR review adapter

The existing `pr-review` executable does not support core. There is no
`--environment herdr-core`; `--environment herdr` selects the legacy host and requires its verified
session. Do not choose it merely because `herdr` is installed or treat `HC_TERMINAL_ID` as legacy
session evidence. Report the unsupported route before launch side effects rather than silently
fall back. A separately authorized manual review is not a prepared executable run.

An explicit prepared context retains its recorded host, adapter, checkout and reviewer session.
Use its trusted run-local instructions and live adapter validation there. Reading that context in
core neither migrates it nor permits recreating or impersonating its reviewer; retain the existing
resources and report the identity blocker if the recorded host cannot be verified.

## Cleanup is separate for terminals and checkouts

After explicit cleanup approval, remove only a terminal this run actually started and whose full
recorded address, live identity and saved/inactive state are proven. `hc ls` includes the user's
other terminals: list membership, parent labels or an idle status alone do not prove ownership or
saved work. Adopted, user-owned, unknown, running, blocked or pending terminals remain intact.

Follow live `hc --skill` and help: for an eligible owned terminal use `hc kill <recorded-address>`,
then `hc rm <recorded-address>`. On a failure retain the identity/evidence and report it; never
broaden cleanup or restart/stop the shared core. Do not kill the caller to clean its checkout.
Child lifetime may be tied to its parent, so record actual launch lifetime options and do not infer
that a terminal or its result survives parent exit.

Terminal removal does not remove a Worktrunk checkout or authorize branch deletion. Follow the
recorded [Worktrunk owner](worktrunk.md) cleanup route separately, from outside the checkout, only
when its own integration, saved/inactive and authorization requirements hold. Retain review
artifacts; posting a review never triggers either cleanup automatically.
