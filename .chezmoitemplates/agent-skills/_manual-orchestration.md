# Bounded Run and Handoff Contract

Apply these invariants to runs that need durable artifacts and independent adoption. They do not
require a transport-specific launch schema, provider discovery, or a second execution backend.

## Private artifacts and identity

After validating inputs, create one unique run directory under
`${MAD_STATE_DIR:-$HOME/.local/state/mad}/runs/<run-id>/` with mode `0700`; files are `0600`.
Create separate attempt directories; never overwrite an earlier attempt or revision. Keep detailed
requirements, results, review packages, and decision requests in external artifacts. Shared audit
records contain only sanitized identity, route, status, counts, verification summaries, and absolute
artifact references, never prompts, raw transport responses, secrets, or source/diff contents.

Record the repository, parent path/branch, resolved commit base, task/dependency identity, execution
route (`omp-internal` or `herdr-cli`), actual child ID, allowed files, attempt/round budget, timestamps,
verification owner, status, and parent adoption decision. Use actual runtime IDs, not predicted IDs.
A worktree record includes owner (`herdr`, `worktrunk`, or `external`), absolute path, branch, base
SHA, workspace/pane IDs only when they exist, integration state, liveness, and cleanup state.
Backend/provider helpers retained for other consumers do not gate this workflow.

## Dependency and scope gate

Before writers start, validate dependencies, task references, cycles, and same-wave file collisions.
The retained dependency parser/validator can check structured plans:

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
"$MAD_SCRIPTS/plan-dependency-validate" "$PLAN_FILE"
"$MAD_SCRIPTS/plan-dependency-validate" --waves "$PLAN_FILE"
```

For a small fanout without that plan format, record the equivalent dependency and file ownership
checks directly. Do not force a rigid schema onto unrelated tasks. A later dependency can start
only after its actual prerequisites are adopted; independent ready nodes need not wait for an
unrelated slow node. One integration owner resolves shared interface changes.

Each result names its task, status, changed files, artifact paths, verification (command, cwd, exit
code, or not-run reason), concerns, and decision request when blocked. Existing role result schemas
may be used where applicable. `BLOCKED`/`NEEDS_CONTEXT`, missing artifacts, unknown liveness, and
invalid scope cannot become successful merely because a CLI exited or a child said “done”.

## Review and bounded escalation

Default review/fix limit: four review rounds total, round 0 initial review and rounds 1–3 repairs
with re-review. Record a smaller limit where appropriate. Never create a fifth round or a fixer per
finding. Fix scope names the task, repository-relative allowed files, initial finding IDs, and an
absolute out-of-scope observations path. Changed files must be a subset of that scope.

Build fixed packages with:

```bash
"$MAD_SCRIPTS/review-bundle" \
  --cwd "$WORKTREE_PATH" --base "$PACKAGE_BASE" --head "$PACKAGE_HEAD" \
  --out "$ATTEMPT_DIR/review-package.diff"
```

Use recorded immutable range endpoints, not guessed `HEAD~1`. A new fix revision requires a fresh
package. Validate finding IDs, verdict, package identity, and `cannotVerify` items before adoption.
Preserve an explicit open-findings list rather than carrying findings only in parent prose.
Out-of-scope observations are read-only and do not authorize extra work; present them once at the
final gate. Scope expansion requires a new approved task.

For final Critical/Important findings, permit at most one approved final fix and one final re-review.
Remaining findings are unresolved; do not restart the final loop. A semantic escalation judge can
recommend only permitted actions within the recorded attempt budget, not freely choose provider,
model, permissions, or ownership. Deterministic errors need correction/evidence, not a judge.
At the limit, preserve artifacts and report the precise required decision.

## Lifecycle and failure preservation

Create a child/resource once and record acceptance. For OMP, use actual completion notifications
and its documented wait mechanism. For a Herdr CLI, readiness and prompt submission are separate
from task completion: inspect the same agent/pane and result artifacts. Do not infer success from
idle alone. Track running, completed, blocked, failed, or unknown and independently adopt results.

Timeout/transport error/unknown state never means successful completion or proof the child stopped.
Do not retry create, launch a replacement, switch backend, or remove a worktree while liveness is
uncertain. Any stop uses the same resource's documented mechanism and records confirmed state.
Keep failures, artifacts, exact IDs/paths, and ownership records. Resume only after inspecting the
existing resource; answering a decision does not permit overwriting the previous attempt.

## Integration and cleanup

Hidden write isolation uses Worktrunk's actual `--format json` and `--no-hooks` route. No Herdr
workspace, tab, or pane is created for write isolation alone. The child base is the committed parent
base; parent uncommitted changes are not automatically copied. A dedicated interactive Herdr
worktree remains Herdr-owned even if Worktrunk can list it.

The parent checks result, scope, diff, commit identity when applicable, and verification before
adoption. Integrate authorized child commits into the recorded parent branch in dependency order;
never use Worktrunk's default-branch merge as an automatic integration step. On conflict, retain
pending state and stop dependent integration. Do not abort an unrelated user merge.

Distinguish `pending`, `merged`, `declined`, and `retained`. Cleanup is optional and only follows an
explicit integration/cleanup decision for owned, saved, inactive resources. Unknown/external owner,
active child, dirty checkout, failure, pending integration, and retained work prohibit removal.
Use the creating owner's removal route without force/clobber. A declined checkout may be removed
only after explicit rejection while its branch/artifacts are retained. Branch deletion is a separate
authorized action and must not destroy unintegrated work. Failed removal preserves the ledger.

## Completion gate

The parent independently validates acceptance, adopted attempts, affected callers, artifact
identity, changed files, scope, review verdict, fresh verification, integration, and retention/removal.
Report exact paths/IDs for unresolved or parked resources and not-run checks. A child report or a
backend success response is never completion evidence by itself.
