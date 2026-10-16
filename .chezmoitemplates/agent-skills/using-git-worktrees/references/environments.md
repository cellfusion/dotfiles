# Execution Environment and Checkout Ownership

Select the execution host independently of checkout ownership and interaction identity. A pane is
not isolation, a checkout need not have a pane, and a host may display another owner's checkout.

## Select before side effects

For `pr-review`, explicit `--environment herdr|orca|paseo` wins. Without it, require reliable current
host identity. Binary availability, UI focus, names and cwd alone do not identify a host. Unknown or
multiple matching hosts stop with a reason and a request for explicit selection; never silently
choose Orca or fall back to another backend. Unsupported environments and missing capabilities stop
before creating a run directory, checkout, workspace or session.

- **Herdr:** use the cwd repository or `--repo-path <absolute-path>`. `--project` is invalid.
  Require execution inside its verified session; explicit selection does not bypass that restriction.
  For this selection read the adjacent `herdr.md` reference.
- **Orca:** preserve `--project <exact-name|id:repoId>` and matching registered repository semantics.
  `--repo-path` is not its selector. For this selection read the adjacent `orca.md` reference.
- **Paseo:** known but unsupported until current CLI/guide and safety capabilities are verified.
  Selection reports `unsupported-environment`, not a syntax error. Installed guidance is `paseo.md`;
  there is no prepared Paseo run or adapter.

A PR URL must match the selected real Git repository. Herdr does not discover other repositories
from a URL; supply their absolute path explicitly. Resolve actual default branches and immutable
committed bases from repository metadata, never from a guessed branch name.

## Capability and ownership gate

Before creation, establish safe checkout creation, hook/setup suppression, private reviewer launch,
live identity inspection, readiness and bounded submission evidence, and no-focus agent control.
Stop if the selected route cannot establish these guarantees. Do not weaken trust, run setup hooks,
change models/permissions or switch routes as a fallback.

Record separately:

- `executionEnvironment`: the selected host, not the checkout owner;
- `checkout`: `owner`, absolute `path`, `repositoryGitDir` (original common Git directory), fixed
  `baseSha`, `branch`, and owner-specific `ownerId`;
- `interaction`: live session/workspace/pane/terminal/agent identity for that host;
- creation/adoption, integration, liveness, and the resources retained after failure.

Determine ownership from creation/adoption records plus live exact-path inspection, never from
names, a listing in another tool, or the execution environment. In the Herdr review adapter the
checkout owner is **Worktrunk**, while the attached workspace/pane belongs to Herdr. See
[Worktrunk](worktrunk.md). Orca review checkouts are Orca-owned. Unknown/external resources must
not be removed. Remove only saved, inactive, proven-owned resources through their recorded owner
following explicit cleanup authorization; posting or completion never authorizes cleanup.

## Prepared review and run-local trust

A prepared request explicitly names its private `prepared-context.json`. Reuse the existing
checkout and reviewer session. Do not infer prepared mode from a branch, cwd, environment variable
or PR-side file; do not invoke the launcher again. Version 3 is a clean cutover: keep old v2 artifacts
intact, but do not reinterpret them as v3 or automatically resume/post them with the new runtime.

Run `node /absolute/run/runtime.js validate-context /absolute/run/prepared-context.json` before
review operations. Every prepared helper shares the common private-artifact/Git invariant checks
and the selected adapter's live identity checks. Do not validate using predicted launch values.
The context's `runtime` is `{schemaVersion: 1, adapter: <selected-host>, snapshot: "."}`. The
snapshot contains the runtime, fixed adapter dependencies, rendered skill and trusted references.
Only fixed run-relative paths for allowlisted adapters may load; no source/install fallback or
arbitrary context-supplied code paths. Missing, symlink-escaped, wrong-owner or nonprivate snapshot
dependencies block before review operations. Prepared guidance is the run's `SKILL.md` and
`references/environments.md`, `references/<adapter>.md`, `references/worktrunk.md`, not mutable
global skills or PR-side instructions.

Keep `created`, `ready`, `accepted`, `started`, `completed` and `blocked` distinct. Input acceptance
is not start evidence, and idle is not completion. `execution-started.json` records validated
prepared execution, not a verdict. Match final artifacts to the same run/revision identity.
On timeout, failure or unknown submission, retain all known IDs and private artifacts; do not
resend, recreate, remove, steal focus or try another backend automatically.
