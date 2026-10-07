#!/usr/bin/env bash
# Exercise real Worktrunk isolation and owner-gated removal, not source wording.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"
SCRIPT="$REPO_ROOT/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-worktree"

if ! command -v wt >/dev/null 2>&1; then
  fail_check 'Worktrunk is required for the isolation boundary test'
  assert_summary
  exit 1
fi
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work/home" XDG_CONFIG_HOME="$work/home/.config"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=mad GIT_AUTHOR_EMAIL=mad@example.invalid
export GIT_COMMITTER_NAME=mad GIT_COMMITTER_EMAIL=mad@example.invalid
export MAD_STATE_DIR="$work/state"
unset HERDR_ENV HERDR_WORKSPACE_ID HERDR_PANE_ID
mkdir -p "$XDG_CONFIG_HOME/worktrunk" "$work/demo/.config" "$work/checkouts"
ln -s "$work/checkouts" "$work/checkout-alias"
cat > "$XDG_CONFIG_HOME/worktrunk/config.toml" <<TOML
worktree-path = "$work/checkout-alias/{{ repo }}-{{ branch | sanitize }}"
pre-start = "touch '$work/user-hook-ran'"
pre-remove = "touch '$work/user-remove-hook-ran'"
TOML
repo="$work/demo"
git -C "$repo" init -q -b main
printf 'seed\n' > "$repo/data.txt"
cat > "$repo/.config/wt.toml" <<TOML
pre-start = "touch '$work/project-hook-ran'"
pre-remove = "touch '$work/project-remove-hook-ran'"
TOML
git -C "$repo" add data.txt .config/wt.toml
git -C "$repo" commit -q -m seed
base="$(git -C "$repo" rev-parse HEAD)"
printf 'uncommitted prerequisite\n' > "$repo/data.txt"
printf 'private parent-only file\n' > "$repo/local.txt"
parent_cwd="$PWD"

field() {
  node -e 'process.stdout.write(String(JSON.parse(process.argv[1])[process.argv[2]]))' "$1" "$2"
}
reject() {
  local status=0
  node "$SCRIPT" "$@" >"$work/rejected.out" 2>"$work/rejected.err" || status=$?
  assert_eq "$status" 2 "rejects $*"
}

create_status=0
created="$(node "$SCRIPT" create --repo "$repo" --run-id r1 --node impl-1 --base "$base")" || create_status=$?
assert_eq "$create_status" 0 'creates hidden isolation through real Worktrunk'
if [ "$create_status" -ne 0 ]; then
  assert_summary
  exit 1
fi
branch="$(field "$created" branch)"
checkout="$(field "$created" path)"
record="$(field "$created" ownershipRecord)"
assert_eq "$checkout" "$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$checkout")" 'records canonical checkout identity across directory aliases'
assert_eq "$(field "$created" owner)" worktrunk 'records Worktrunk ownership'
assert_eq "$(field "$created" workspaceId)" null 'has no workspace ownership'
assert_eq "$(field "$created" paneId)" null 'has no pane ownership'
assert_eq "$(git -C "$checkout" rev-parse HEAD)" "$base" 'uses the fixed committed parent base'
assert_eq "$(cat "$checkout/data.txt")" seed 'does not copy tracked parent prerequisites'
[ ! -e "$checkout/local.txt" ] && pass 'does not copy untracked parent files' || fail_check 'does not copy untracked parent files'
assert_eq "$PWD" "$parent_cwd" 'leaves the parent cwd unchanged'
assert_eq "$(cat "$repo/data.txt")" 'uncommitted prerequisite' 'preserves the parent dirty tree'
[ ! -e "$work/user-hook-ran" ] && [ ! -e "$work/project-hook-ran" ] && pass 'suppresses user and project creation hooks' || fail_check 'suppresses user and project creation hooks'
node -e 'const fs=require("node:fs");if((fs.statSync(process.argv[1]).mode&511)!==384)process.exit(1)' "$record" && pass 'ownership record is private' || fail_check 'ownership record is private'
reject create --repo "$repo" --run-id r1 --node impl-1 --base "$base"
listed="$(node "$SCRIPT" list --repo "$repo")"
assert_eq "$(node -e 'process.stdout.write(String(JSON.parse(process.argv[1]).length))' "$listed")" 1 'duplicate create does not add another task checkout'

reject remove --repo "$repo" --branch "$branch"
reject remove --repo "$repo" --branch "$branch" --integration pending --inactive
printf 'unsaved\n' > "$checkout/unsaved.txt"
reject remove --repo "$repo" --branch "$branch" --integration declined --inactive
[ -d "$checkout" ] && pass 'dirty removal retains checkout' || fail_check 'dirty removal retains checkout'
rm "$checkout/unsaved.txt"
printf 'feature\n' > "$checkout/feature.txt"
git -C "$checkout" add feature.txt
git -C "$checkout" commit -q -m feature

# Integration into a different checkout or branch is not integration into the owner.
git -C "$repo" worktree add -q -b other-parent "$work/other-parent" "$branch"
reject remove --repo "$work/other-parent" --branch "$branch" --integration merged --inactive --delete-branch
if [ ! -d "$checkout" ]; then
  fail_check 'different parent checkout cannot remove the pending child'
  assert_summary
  exit 1
fi
git -C "$repo" switch -q -c switched-parent "$branch"
reject remove --repo "$repo" --branch "$branch" --integration merged --inactive --delete-branch
if [ ! -d "$checkout" ]; then
  fail_check 'switching the owning parent branch cannot remove the pending child'
  assert_summary
  exit 1
fi
git -C "$repo" switch -q main
reject remove --repo "$repo" --branch "$branch" --integration merged --inactive
reject remove --repo "$repo" --branch "$branch" --integration declined --inactive --delete-branch
removed="$(node "$SCRIPT" remove --repo "$repo" --branch "$branch" --integration declined --inactive)"
assert_eq "$(field "$removed" removed)" true 'removes explicitly declined saved inactive checkout'
assert_eq "$(field "$removed" branch_deleted)" false 'retains declined branch'
git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" && pass 'declined commits remain reachable' || fail_check 'declined commits remain reachable'
[ ! -e "$work/user-remove-hook-ran" ] && [ ! -e "$work/project-remove-hook-ran" ] && pass 'suppresses removal hooks' || fail_check 'suppresses removal hooks'
[ -f "$record" ] && pass 'retains ownership evidence after removal' || fail_check 'retains ownership evidence after removal'

create_status=0
merged="$(node "$SCRIPT" create --repo "$repo" --run-id merged --node impl --base "$base")" || create_status=$?
assert_eq "$create_status" 0 'creates the integrated cleanup fixture'
if [ "$create_status" -ne 0 ]; then
  assert_summary
  exit 1
fi
merged_branch="$(field "$merged" branch)"
removed="$(node "$SCRIPT" remove --repo "$repo" --branch "$merged_branch" --integration merged --inactive --delete-branch)"
assert_eq "$(field "$removed" branch_deleted)" true 'deletes an explicitly authorized integrated branch non-forcing'
git -C "$repo" show-ref --verify --quiet "refs/heads/$merged_branch"
assert_eq "$?" 1 'authorized integrated branch is no longer reachable'

# A matching branch prefix is not proof of ownership.
git -C "$repo" worktree add -q -b mad/external/impl "$work/external" "$base"
reject remove --repo "$repo" --branch mad/external/impl --integration declined --inactive
[ -d "$work/external" ] && pass 'retains external worktree' || fail_check 'retains external worktree'

reject create --repo "$repo" --run-id ../escape --node impl --base "$base"
reject create --repo "$repo" --run-id invalid --node impl --base missing-revision
reject create --repo "$repo" --run-id unknown-option --node impl --base "$base" --force
assert_summary
