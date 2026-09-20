#!/usr/bin/env bash
# mad-worktree が素の git で worktree を作り、既定でブランチを残すことを検査する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$REPO_ROOT/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-worktree"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=mad GIT_AUTHOR_EMAIL=mad@example.invalid
export GIT_COMMITTER_NAME=mad GIT_COMMITTER_EMAIL=mad@example.invalid
export MAD_STATE_DIR="$work/state"

repo="$work/demo"
mkdir -p "$repo"
git -C "$repo" init -q -b main
printf 'seed\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m 'seed'
base="$(git -C "$repo" rev-parse HEAD)"

assert_eq "$(head -1 "$SCRIPT")" '#!/usr/bin/env node' 'shebang は node である'

created="$(node "$SCRIPT" create --repo "$repo" --run-id r1 --node impl-1 --base "$base")"
assert_eq "$(printf '%s\n' "$created" | wc -l | tr -d ' ')" 1 'create の出力は 1 行である'
branch="$(printf '%s' "$created" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).branch))')"
wt_path="$(printf '%s' "$created" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).path))')"
setup="$(printf '%s' "$created" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>process.stdout.write(JSON.parse(s).setup))')"
assert_eq "$branch" 'mad/r1/impl-1' 'branch は mad/<run-id>/<node-id> である'
assert_eq "$wt_path" "$MAD_STATE_DIR/worktrees/demo/mad-r1-impl-1" 'worktree の置き場所は MAD_STATE_DIR の下である'
assert_eq "$setup" 'skipped' '.config/wt.toml が無ければ setup は skipped である'
assert_not_contains "$wt_path" "$repo/" 'worktree はリポジトリの作業ツリーの外にある'
[ -d "$wt_path" ] && pass 'worktree のディレクトリができる' || fail_check 'worktree のディレクトリができる'

listed="$(node "$SCRIPT" list --repo "$repo")"
assert_contains "$listed" 'mad/r1/impl-1' 'list は mad/ の worktree を返す'

printf 'unmerged\n' > "$wt_path/feature.txt"
git -C "$wt_path" add feature.txt
git -C "$wt_path" commit -q -m 'feature'

removed="$(node "$SCRIPT" remove --repo "$repo" --branch mad/r1/impl-1)"
assert_contains "$removed" '"removed":true' 'remove は worktree を消す'
assert_contains "$removed" '"branch_deleted":false' 'remove は既定でブランチを消さない'
assert_contains "$(git -C "$repo" branch --list mad/r1/impl-1)" 'mad/r1/impl-1' 'ブランチは残る'

again="$(node "$SCRIPT" remove --repo "$repo" --branch mad/r1/impl-1 --delete-branch 2>/dev/null)"
assert_contains "$again" '"branch_deleted":false' '未 merge のブランチは削除に失敗する'
assert_contains "$(git -C "$repo" branch --list mad/r1/impl-1)" 'mad/r1/impl-1' '削除に失敗したブランチは残る'

node "$SCRIPT" bogus --repo "$repo" >/dev/null 2>&1
assert_eq "$?" 2 '未知のサブコマンドは exit 2 である'

node "$SCRIPT" --help >/dev/null 2>&1
assert_eq "$?" 0 '--help は exit 0 である'

assert_not_contains "$(cat "$SCRIPT")" 'git branch -D' 'git branch -D を使わない'
assert_not_contains "$(cat "$SCRIPT")" 'create_workspace' 'Paseo の workspace を作らない'

assert_summary
