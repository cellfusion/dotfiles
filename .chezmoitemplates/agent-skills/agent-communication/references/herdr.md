# Repository Workspace Communication Through Herdr

Read the installed `herdr` skill first. Requires `HERDR_ENV=1`; outside Herdr do not inspect or
control the focused session. Use the installed CLI as authority. The commands below were checked
against Herdr 0.9.3; see [Agent automation](https://herdr.dev/docs/0.9.3/agent-automation/).

## Resolve the target repository and workspace

1. Resolve the requested repository's real absolute path and Git root without changing checkout.
   Inspect existing worktree ownership when relevant using `using-git-worktrees`.
2. Run `herdr workspace list`, then `herdr pane list --workspace <returned-workspace-id>` for
   plausible candidates. Workspace labels are hints only. Herdr 0.9.3 workspace get does not expose
   a universal `cwd`; resolve ownership from pane cwd/foreground_cwd, recorded worktree metadata
   and the actual repository root. Do not invent `.result.workspace.cwd`.
3. Run `herdr agent list` and `herdr agent get <actual-target>` to confirm kind, session, pane,
   cwd and status. Match the requested repository/checkout and assignment. If multiple candidates
   remain and metadata cannot disambiguate them, ask which owner rather than guessing.
4. Reuse an appropriate idle/done owner. If its cwd is another worktree of the repository, do not
   silently switch the requested checkout: establish the approved write location first. Do not
   hijack a busy owner, terminate it, or create competing writers while its assignment is unclear.

## Start an owner when none exists

Cross-repository requests explicitly authorize work in the target repository's workspace. If no
matching workspace exists, create it there without focus:

```bash
herdr workspace create --cwd "$TARGET_REPO" --label "$REPO_LABEL" --no-focus
```

Read workspace/root pane IDs from `.result.workspace.workspace_id` and
`.result.root_pane.pane_id`. Record ownership. Do not retry creation after an uncertain response.
If a matching workspace exists but no available owner, reuse a confirmed available shell pane;
otherwise create a no-focus tab in that workspace:

```bash
herdr tab create --workspace "$WORKSPACE_ID" --cwd "$TARGET_REPO" --label "$TASK_LABEL" --no-focus
```

Read its `.result.root_pane.pane_id`. Confirm the shell is available (no foreground command/editor)
and start the default OMP with a unique live name, preserving native model/permission defaults:

```bash
herdr agent start "$AGENT_NAME" --kind omp --pane "$PANE_ID" --timeout 120000
```

A different requested agent kind takes precedence. Do not create a worktree for communication alone,
copy dirty prerequisites or run setup hooks. Startup readiness is not completion. On startup failure
retain returned IDs and inspect; do not launch another owner to hide the failure.

## Send and inspect

Use an explicit actual target, never omitted focused-pane defaults. Recheck recipient session,
kind, cwd and assignment immediately before sending. Get followed by prompt is not proven atomic
against same-kind occupant replacement; reject mismatched result identity. Do not send to self.

```bash
herdr agent get "$TARGET"
herdr agent prompt "$TARGET" "$BOUNDED_REQUEST" --wait --timeout 120000
herdr agent read "$TARGET" --source recent-unwrapped --lines 120
```

The request includes sender/return target and `request_id`. Shell variables above must be actual
validated values, and prompt text remains a quoted argument, never eval'd. Use normal `--wait`;
`--until` is only for a deliberate state-specific workflow.

Get/list/prompt responses are JSON. CLI `agent read` prints terminal text directly (the socket API,
not CLI text, exposes `.result.read.text`). Read the correlated answer before adopting it.

`agent prompt` validates a live agent; raw `pane run/send-text/send-keys` does not. Do not use raw
pane input as fallback when an agent rejects input. It may now be a shell or editor.

## State and output caveats

- `idle` and `done` mean input-ready; done is an unseen idle completion, not task-specific proof.
- `blocked` requires inspecting the question/approval. Do not grant permissions automatically.
- `unknown` is unresolved, not success. Avoid sending until identity/readiness is established.
- `--wait` follows lifecycle, not one prompt. If sent while already working, another turn can satisfy
  it. Default to idle/done, then correlate `request_id`. `completion_seq` is not a request ID.
- Timeout/`agent_prompt_stalled` may occur after submission. Read the same recipient before any
  explicit retry; never automatically resend or create a replacement.
- `agent wait` has no default timeout. Always supply a finite timeout and wait only when necessary.
- For idle supported fullscreen agents, recent reads can collect alternate-screen history through
  mouse scrolling. While working/blocked/unknown, a history read may fail with `agent_not_idle`;
  use a passive visible read for diagnosis, not a completion claim.
- If a complete reply remains unavailable, ask the same owner to write it to a permitted private
  shared absolute path and return that path. Do not require file output for every initial request.

## Cross-repository integration and retention

Send each owner only the approved common contract and its own scope. Owners verify local behavior;
the parent checks contract compatibility and the combined scenario. Do not silently change API
contracts or forward the full parent transcript. Record actual workspace/pane/session identity and
artifact paths so clarification reaches the same owner. If a pane moves, use returned new IDs or
its current unique agent name instead of guessing a new workspace-qualified ID.

Do not close reused workspaces or agents. Close newly created resources only when specifically
authorized and saved/inactive; preserve unknown, busy, failed or unsaved work. Workspace ownership
and worktree ownership are separate. Never stop the main Herdr server to finish a communication task.
