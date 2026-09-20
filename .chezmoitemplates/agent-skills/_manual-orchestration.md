# Strict MAD Run Contract

This contract applies only after the parent has chosen a multi-child strict MAD run. It does not decide
whether to use MAD, a single child, or direct work. Do not execute it for a simple task, a single
research child, or a plan run handled by `executing-plans`.

## Backend and path initialization

A strict run uses exactly one backend for its lifetime: `paseo-cli` or `paseo-mcp`. The default is
`paseo-cli`; select `paseo-mcp` explicitly when provider-specific features are required. Run state
lives under `${MAD_STATE_DIR}/runs/<run-id>/`. Discovery,
model discovery, creation, waiting, stopping, and state recording use that backend. If it is
unavailable after the run starts, stop in `waiting_for_user`; do not switch backends or retry the
same create.

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
MAD_BACKEND="${MAD_BACKEND:-paseo-cli}"
case "$MAD_BACKEND" in
  paseo-cli) MAD_ADAPTER="$MAD_SCRIPTS/paseo-cli-adapter" ;;
  paseo-mcp) MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter" ;;
  *) printf 'unsupported MAD_BACKEND: %s\n' "$MAD_BACKEND" >&2; exit 2 ;;
esac
MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"
MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"
MAD_REVIEW_BUNDLE="$MAD_SCRIPTS/review-bundle"
MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"
MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"
MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"
MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"
MAD_OUTCOME_RECORD="$MAD_SCRIPTS/mad-outcome-record"
MAD_ESCALATION_CONTROLLER="$MAD_SCRIPTS/mad-escalation-controller"
MAD_OUTCOME_LOG="${MAD_OUTCOME_LOG:-$MAD_STATE_DIR/metrics/attempt-outcomes.jsonl}"
MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/agent-config}"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
```

`MAD_STATE_DIR` contains run directories and worktrees. Do not export it merely to initialize the
contract. State, handoffs, logs, prompts, requests, and evidence are mode `0600`; directories are
mode `0700`. Do not store credentials, raw responses, prompts with secrets, auth history, URLs,
source contents, or unbounded child output in state/log artifacts. These values are prohibited even
when a transport returns them.

`MAD_OUTCOME_LOG` is append-only sanitized JSONL. After an independently verified attempt, create a
`mad-attempt-outcome-v1` record and use `MAD_OUTCOME_RECORD` to record route/model/effort,
verification, status, retry count, and sanitized usage. For an accepted CLI child, the optional
usage inspection is `inspect-agent --child-ref <safe-id>`. Keep transport call logs and outcome logs
separate.

## Provider and model resolution

Materialize and validate the provider enumeration before discovery. Use only the provider IDs in the
validated enumeration. List providers once, list models once per eligible provider, and do not query
unselected providers. Save only validated mode `0600` snapshots.

Resolve each child with the configured generator:

```bash
"$MAD_GENERATOR" --input "$AGENT_CONFIG" resolve \
  --project "$PROJECT" --role "$ROLE" --provenance "$PROVENANCE" \
  --complexity "$COMPLEXITY" --work-class "$WORK_CLASS" --round "$ROUND" \
  --snapshot "$RUN_DIR/snapshot.json" > "$RUN_DIR/launch.json"
```

Use `mad-dispatch` for initial children, `mad-fix` for fixes, and `mad-review` for review children.
Use the task's explicit complexity or `routine` when absent. Resolve work class from explicit task
metadata or the repository policy. A successful launch must pass strict validation: supported mode,
allowed features, declared scalar types, selected environment, and backend compatibility. Exit 4
means no candidate and must become `waiting_for_user`; exit 2 means invalid input and must become
`failed`; neither may create a child.

The CLI backend accepts only CLI-compatible launches with no unsupported provider features. The MCP
backend may pass the full validated feature set. Never reconstruct provider, model, effort, or
features in the parent.

## Create request and attempt state

Implementer create order is fixed:

```text
task excerpt -> execution context -> enrichment -> request build/assert -> prepare marker -> create -> sanitized response
```

For each attempt, create fresh files in its private attempt directory:

- `task-excerpt.md`
- `execution-context.md`
- `brief.md`
- request, result, handoff, state, and log artifacts

Required context fields include run/node/task/attempt IDs, phase, work class, role prompt/schema,
attempt base SHA, workspace cwd, round, result/handoff/log paths, decision path, constraints path,
review scope path, and open-findings path. All paths are absolute. `ATTEMPT_BASE` is the immutable
SHA captured at attempt start. Initial attempts use `not-applicable` review paths; fix attempts use
existing mode `0600` scope/open-finding files.

The implementer prompt receives only the fresh absolute `brief.md`, not the full plan or conversation
history. The brief contains the task excerpt, execution context, role/schema references, constraints,
and required artifact destinations.

The exact create request contains only:

```text
title, workspaceId, initialPrompt, notifyOnFinish, provider, settings
settings: modeId, thinkingOptionId, features
```

`settings.modeId` must be `auto`; `provider` is `<provider>/<model>`; features are the resolved
feature values. Validate the request with `assertMadCreateRequestV1`, then use `--prepare-create`
exactly once per attempt. The prepare marker is mode `0600`, created with exclusive semantics, and
must exist before the backend create. A second or concurrent create is rejected without changing
state or call logs.

Create once per child. Reduce an accepted response to the exact safe shape
`{"status":"accepted","childRef":"<safe-id>"}`. Before acceptance, `create_accepted=false`
and no child ref exist. After acceptance, `create_accepted=true`, `state=running`, and a safe child
ref are written together. The accepted flag remains true for every later state.

## Call logs and lifecycle

A strict call log is `{version:1,type:"mad-call-log",events:[...]}`. Events have consecutive `seq`
values and one of the declared operations: provider enumeration, provider/model listing, snapshot,
resolve, request build, create, wait, stop, or failure. Reject unknown keys, unknown operations,
invalid sequence numbers, URLs, or raw responses. Record counts, safe IDs, exit codes, artifact
paths, and summarized statuses only.

Each accepted child has one create and one wait watcher. Use the selected backend adapter for wait and
stop. Reduce wait to `idle`, `timeout`, or `error`; reduce stop to `stopped` or `error`. Timeout,
unknown state, transport failure, or malformed response is unresolved, not success. Stop once through
the same backend and record the result before setting `stopped`.

Run outcomes follow this table:

| Event | State | Creates |
|---|---|---:|
| discovery/model/snapshot failure | `waiting_for_user` | 0 |
| launch exit 4 | `waiting_for_user` | 0 |
| invalid launch/request | `failed` | 0 |
| environment mismatch | `waiting_for_user` | 0 |
| prepare/marker/request validation failure | unchanged | 0 |
| create rejection or malformed acceptance | `failed` | 1 |
| accepted create | `running` | 1 |
| child decision request | `unresolved` | parent stops |

## Plan dependency gate

Validate task references, dependencies, literal `Files:` paths, cycles, and wave conflicts:

```bash
"$MAD_PLAN_VALIDATE" "$PLAN_FILE"
"$MAD_PLAN_VALIDATE" --waves "$PLAN_FILE"
```

Use the `--waves` output as the implementation order. Do not create a later wave before every task
in the current wave has been adopted or explicitly declined. A dependency or file-collision failure
stops the run before any implementer is created.

## Review/fix scope

Review/fix loops have `max_rounds: 4`: round 0 is the initial task review; rounds 1-3 are bounded
fix/re-review rounds. Do not create a fifth round or a per-finding fixer. Create one mode `0600`
review scope containing the task, repository-relative allowed files, immutable initial finding IDs,
and an absolute out-of-scope observations path. Fix changed files must be a subset of allowed files.

Create fixed review packages through one command:

```bash
"$MAD_REVIEW_BUNDLE" \
  --cwd "$WORKSPACE_CWD" --base "$PACKAGE_BASE" --head "$PACKAGE_HEAD" \
  --out "$ATTEMPT_DIR/review-package.diff"
```

Use the run base and post-implementation HEAD for round 0; the HEAD immediately before the round's
fix and after that fix for later rounds. Never use `HEAD~1` as a substitute for the recorded base.
Validate package range and reviewer verdict before adoption. Record `cannotVerify` items individually,
then create the next open-findings list through the validator. Never carry findings forward only as
parent prose.

Keep out-of-scope observations in a mode `0600` observations file. Do not start a fix for them in
the current run. Present them once at the final decision gate; an approved scope expansion starts a
new task or run.

If final review has Critical/Important findings, run one bounded final-fix and one final re-review.
Do not restart final-fix, create per-finding fixers, or relaunch the final reviewer. Remaining findings
become `unresolved`/`waiting_for_user`.

## Implementer result and integration

After an implementer finishes, branch on its validated status. Run the post-commit validator only
for `DONE` and `DONE_WITH_CONCERNS` results:

```bash
"$MAD_VALIDATE" --check-implement-result \
  --workdir "$WORKSPACE_CWD" --base "$ATTEMPT_BASE" --round "$ROUND" \
  --result-file "$RESULT_FILE"
```

A validator exit `2` becomes `waiting_for_user`; copy its one-line stderr reason into the decision
request. `BLOCKED` and `NEEDS_CONTEXT` do not run the post-commit check. Preserve their summary and
non-null `decisionRequestPath`, keep integration `pending`, and do not remove the worktree.

The result contract includes `DONE`, `DONE_WITH_CONCERNS`, `BLOCKED`, `NEEDS_CONTEXT`, `summary`,
`changedFiles`, and `decisionRequestPath`. A write role's decision request is an absolute path. Do
not create a child or claim success when the result contract is invalid.

## Worktree and integration ledger

Strict MAD worktrees are created by `mad-worktree` outside the repository. Under the Paseo MCP
backend, pass the returned absolute path to `mcp__paseo__create_workspace` with `isolation: local`;
Paseo attaches a workspace to the existing checkout and must not create a second Git worktree. Keep
one `worktrees.json` ledger per run with node, path, branch, resolved 40-character base,
integration, removed, and branch-deleted fields. Accepted attempts retain `backend_handle` and
`liveness` in their state after creation.

Implement and spike children use:

```bash
"$MAD_WORKTREE" create --repo <repo-root> --run-id <run-id> \
  --node <node-id> --base <resolved-40-character-sha>
```

Worktrees live outside the repository at `${MAD_STATE_DIR}/worktrees/<repo>/<branch>`. The ledger
records node, path, branch, base, integration (`pending`, `merged`, or `declined`), removed, and
branch-deleted. Never overwrite an existing ledger entry.

Review children read fixed review packages rather than the worktree. Build the package before
removing the worktree. A failed package build fails the run. After an explicit integration decision:

- `merged`: remove the owned worktree and delete the branch only when the remover confirms it
- `declined`: remove the checkout but retain the branch
- `pending` or failed removal: retain the ledger and do not mark the run `ok`

Integrate adopted tasks in task-number order:

```bash
git -C "$PROJECT_ROOT" merge --no-ff "mad/<run-id>/<node-id>"
```

Only a successful merge sets integration to `merged`. On conflict, run `git -C "$PROJECT_ROOT" merge --abort`, keep integration `pending`, write a decision request with repository-relative conflict
paths, the two task numbers, and both tasks' `Depends on` / `Files:` metadata, then stop the rest of
the wave and all later waves. Do not remove a conflicted worktree.

## Decision requests and completion

If a child requests a decision, preserve its structured question, options, recommendation, and
reason in an external decision artifact. Set run and phase state to `waiting_for_user`. After the
answer, create a new attempt; never overwrite the old one. No answer means `stopped`.

Before marking a run `ok`, independently validate state, adopted attempts, schemas, artifacts,
verification, changed files, scope, integration, and removal. Use `mad-progress status` for progress,
`reap` only for evidence-based stale attempts, and `resume` only to inspect; neither starts a child.
A child report is never completion evidence by itself.
