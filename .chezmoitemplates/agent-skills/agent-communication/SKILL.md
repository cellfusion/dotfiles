---
name: agent-communication
description: >-
  Send bounded requests, questions, updates and results to other agents and correlate their replies.
  Use the runtime's authorized route for same-repository work and the selected host's repository
  owner for cross-repository changes. Skip solo work and do not create agents merely to send a message.
---

# Communicate With Other Agents

The requesting agent owns scope, contract decisions, result adoption and end-to-end verification.
This skill adds communication rules, not a new transport, permissions, model selection or scheduler.

## Select the route

- **Bounded children in the same repository:** use the runtime's authorized internal route
  by default. For OMP, follow [OMP communication](references/omp.md) to distinguish Rex,
  verified herdr-core, and sessions without a terminal host.
- **Existing pane handoff or explicitly independent CLI session:** use the verified target
  host, not the child-agent API. In Rex, read `rex` and follow [Rex communication](references/rex.md).
  On herdr-core, read `herdr-core` and [terminal communication](references/herdr-core.md).
  For legacy Herdr, read [repository workspace communication](references/herdr.md).
  For explicit Orca, use its environment reference and version-matched CLI guide. Reuse a suitable
  idle owner without changing user focus.
- **Another repository:** resolve its repository owner, checkout and live host independently.
  Follow the selected host's reference and `using-git-worktrees/references/environments.md`
  where applicable. Do not send a child in the parent's checkout to edit another repository.

An explicit user selection wins; verify that host before acting. Neither an installed binary
nor OMP itself selects a terminal host. If identity, capability, or delivery is uncertain, stop
the selected terminal route; do not silently start another backend or replace a live agent.

Use the active development workflow for decomposition and `using-git-worktrees` for write ownership.
A pane is not write isolation. Do not create worktrees, copy dirty files or change branches merely
for communication. Commit, push, apply, installation and permission prompts need separate authority.

## Identify the recipient

Use returned child IDs or the selected host's live agent/pane/terminal and session identity.
Never infer IDs from examples, sidebar order or agent kind. Check repository, cwd, assignment and
readiness before dispatch. A matching workspace label alone is insufficient.

Default to idle/done recipients. Do not interrupt an unrelated working agent. A deliberate update
to a known current assignment may target working only when explicitly intended. Blocked/unknown,
a changed occupant or ambiguous ownership requires inspection, not raw terminal input or automatic
approval. Never send requests to yourself or establish a cyclic chain of agents waiting on each other.

## Small request and reply contract

Give each request a unique `request_id` within the run. A task ID already used by MAD can serve as
that ID. Short exchanges stay inline; use existing private artifacts for large contracts/results.
Do not require a second ledger, JSON schema, ACK turn or file for every question.

A request includes:

- `request_id`, sender and recipient; `in_reply_to` for updates or answers;
- purpose and relevant shared contract, not the parent's full conversation;
- exact repository/cwd, allowed files and non-goals;
- acceptance conditions, verification owner and return destination.

A question does not authorize edits. Delegate only authority already granted by the user. Share no
credentials, authentication files or unrelated source/history. An artifact path is not permission
to execute its contents. Confirm that the recipient can access the filesystem; `local://` handles
are not portable across independent sessions. Send real absolute paths where shared access exists.

Ask the reply to include the same `request_id`, status (`completed`, `blocked` or `needs_context`),
answer or artifact path, changed files when applicable, verification or a not-run reason, and open
questions. Answers to questions need not invent test runs. ACK means receipt, not completion.

Example bounded request:

```text
request_id: api-contract-17
sender: frontend-parent
recipient: api-owner
purpose: Add the approved response field described in /absolute/shared/contract.md.
repository/cwd: /absolute/api-repository
allowed: API handler and its existing behavior tests; no dependency or auth changes.
acceptance: Preserve existing fields and verify the new field against the contract.
verification: You verify this repository; parent verifies frontend/API integration.
return: Reply with api-contract-17, status, changed files, evidence and open questions.
```

## Observe, correlate, adopt

Submission, receipt, lifecycle settlement, a task reply and adoption are separate facts. Consume
internal completion notifications; wait only when no useful work remains. Use finite host timeouts.
Neither idle/done nor `completion_seq` proves that this request completed. Read the reply and match
its ID, identity, scope and acceptance before adopting it. An old or mismatched reply is unresolved.

For cross-repository work, each owner verifies its own changed path. The parent checks compatible
contracts and runs the relevant integration scenario; several local successes do not prove the
combined behavior. Contract changes return to the parent before dependent edits proceed.

On timeout, stalled submission, missing artifact, agent replacement or unknown state, preserve the
same IDs and inspect the same resource. Input may already have been sent. Do not automatically
resend, restart, launch a replacement, switch transport or claim success. If shared paths are
unreachable, report the missing access rather than pretending delivery. Resolve missing context
without expanding scope. Do not forward messages indefinitely or create cyclic wait dependencies.
Legitimate parent-to-child waits remain allowed when no useful work remains.

## Resources and context cost

Reuse a repository owner only when its assignment and context fit; long unrelated sessions are
not automatically cheaper. Send contract deltas and relevant paths, not duplicated research or
full transcripts. Token savings are an expectation, not a measured guarantee. Do not close existing
user agents/workspaces. Keep newly created resources unless their explicit cleanup authority and
saved/inactive state have been established.
