# Orca Interaction and Checkout Ownership

## Select and inspect the matching CLI

For manual operations, select `ORCA_CLI_COMMAND` when set; otherwise `orca-dev` for
`ORCA_DEV_REPO_ROOT`, otherwise `orca-ide` on Linux outside an Orca terminal, otherwise `orca`.
Never fall back to another build if that executable fails. Read its current `--help`, version and
version-matched CLI guide directly, using the guide location exposed by that executable/help.
Do not invent a guide path, use another build's guide, install a removed skill, or make the removed
`orca-cli`/`computer-use` skills prerequisites. If the matching guide/capability is unavailable,
stop the manual operation with that limitation. Prepared review uses its fixed run-local adapter
and this guidance, not a mutable global guide or skill.

## PR review adapter

Use `pr-review --environment orca --no-focus [--project <exact-name|id:repoId>] [--quick] <PR>`.
The local repository must be registered in the selected Orca instance. A PR URL resolves its
matching registered repository; `--project` selects an exact display name or `id:<repoId>` from any
cwd. When both are supplied they must match. A number without `--project` uses the cwd repository.
Missing or ambiguous matches stop before creation; an explicit registered ID disambiguates.
`--repo-path` is not an Orca selector. An ordinary shell may select Orca explicitly; it is no longer
an implicit default for an unknown host.

The adapter creates one fixed base-SHA worktree with `--setup skip` and one dedicated terminal.
Custom OMP arguments use `terminal create --command`, not the configured `--agent` launcher.
Default shell/configured terminals are retained, not repurposed or closed. The terminal command
sets `umask 077` before OMP exec and uses a run-unique private session directory plus
`autoResume: false` overlay. Keep existing models and approval defaults.

Record `checkout.owner=orca`, its full returned `ownerId` (`repoId::/absolute/path`), path, branch,
base and original common Git directory. `interaction.terminalHandle` is the dedicated terminal's
returned handle. Inspect live worktree/terminal identity with the selected executable, matching
full IDs and exact cwd; do not require Herdr IDs or infer ownership from a path prefix.
Readiness requires `terminal wait --for tui-idle` with `wait.satisfied: true` plus matching live
identity. Submit one explicit skill-read request, not a startup slash command. `accepted: true`
proves only input acceptance; `turn_started` proves submission/start, neither proves completion.
Preserve unknown/failed receipts and resources without resend, restart, recreation or fallback.

## Cleanup

Use the owning executable's version-matched guide and current removal help after separate explicit
cleanup approval. Verify full worktree ID, exact checkout path, dedicated terminal identity and
saved/inactive state before using the Orca worktree/terminal removal route without force. Never
remove it through Herdr or Worktrunk merely because their lists can see the path. Preserve review
artifacts and unknown, dirty, running, failed or pending resources. Posting never authorizes cleanup.
