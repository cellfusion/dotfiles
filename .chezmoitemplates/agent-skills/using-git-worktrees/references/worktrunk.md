# Worktrunk Checkout Owner

Worktrunk is checkout ownership/isolation, not an interaction host. Hidden child checkouts have no
workspace or pane. A Herdr review workspace may attach a Worktrunk-owned checkout; record the
checkout and workspace identities independently.

## Create from a committed base

For new manual operations read live `wt switch --help` and `wt remove --help`. Check branch
collision and existing ownership first. Use the actual parent root, a unique safe branch and fixed
committed base; do not auto-copy dirty files or change the parent cwd:

```bash
out=$(wt -C "$CALLER_ROOT" switch --create "$CHILD_BRANCH" \
  --base "$BASE_SHA" --no-cd --no-hooks --format json)
WORKTREE_PATH=$(printf '%s' "$out" | jq -er '.path')
```

The interface is `--format json`, not `--json`. Use the returned absolute path, not a predicted
path template. Require `action=created`, `created_branch=true`, and the expected branch. Validate
linked-worktree/common Git directory identity and exact HEAD at base. Record owner `worktrunk`,
`ownerId` as the created branch, path, base, integration `pending` and creation/liveness evidence.
No pane IDs belong to this owner record; an attached host has its own interaction record.
The retained `mad-worktree` helper provides bounded child ownership records.

`--no-hooks` suppresses user and project hooks, including terminal launch and arbitrary setup;
`--no-cd` leaves parent cwd alone. Preserve the configured placement template. Do not run setup,
install, deploy or network commands merely because repository configuration exists, and never
use `wt merge` for automatic integration into default. Required setup needs its own approved
trusted-base procedure. Failed/incomplete creation retains known IDs/path and artifacts; do not
retry creation, choose another owner or silently write in the caller checkout.

## Inspect and remove

A path appearing in `wt list` does not establish Worktrunk ownership. Match its original creation
record, exact branch/path/base and common Git directory. Do not adopt or remove external resources
from naming conventions. A host workspace attached to the checkout must be inspected separately.

After explicit cleanup approval, successful integration or an explicit saved-work decision, and
proof that the checkout and attached processes are inactive, remove from outside the checkout:

```text
wt -C <parent> remove <child-branch> --no-delete-branch --foreground --no-hooks --format json
```

Retain the branch unless its deletion is separately authorized and proven non-forcing. Declined
work retains its branch. Never remove dirty, running, failed, blocked, pending, parked or unknown
resources; preserve ownership records and review artifacts after failure. Do not use host-specific
worktree removal on this checkout, force/clobber, or process reaping as routine cleanup.
