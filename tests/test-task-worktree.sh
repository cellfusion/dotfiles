#!/usr/bin/env bash
# fake の wt / git を PATH の先頭に置き、task-worktree が正しい引数を組み立てることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts/executable_task-worktree"
REPO_ROOT="$CHEZMOI_SOURCE"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/wt" <<'FAKE'
#!/usr/bin/env bash
printf 'wt %s\n' "$*" >> "$FAKE_LOG"
case "$1" in
  switch) printf '{"action":"created","branch":"sdd/t-1","path":"/wt/sdd-t-1","created_branch":true,"base_branch":"main"}\n' ;;
  remove) printf '{"action":"removed"}\n' ;;
esac
FAKE

cat > "$TMP/bin/git" <<'FAKE'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$FAKE_LOG"
[ -n "${FAKE_MERGE_CONFLICT:-}" ] && case "$*" in *merge*) printf 'CONFLICT (content)\n' >&2; exit 1 ;; esac
exit 0
FAKE

chmod +x "$TMP/bin/wt" "$TMP/bin/git"
export FAKE_LOG="$TMP/calls.log"
export PATH="$TMP/bin:$PATH"
export SDD_WT_CONFIG="$HOME/.config/worktrunk/agent.toml"

run_js() { node -e "const w = require('$SCRIPT'); $1"; }

# 作成: agent 専用 config を渡し、herdr フックが走らない形にする。
: > "$FAKE_LOG"
out="$(run_js "console.log(JSON.stringify(w.createTaskWorktree({repoRoot:'$REPO_ROOT', branch:'sdd/t-1', base:'abc1234'})))")"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "wt switch --create sdd/t-1" "worktree をブランチ名で作る"
assert_contains "$log" "--base abc1234" "指定された base から分岐する"
assert_contains "$log" "--no-cd" "シェルの cwd を動かさない"
assert_contains "$log" "--format json" "自動化用の JSON 出力を使う"
assert_contains "$log" "--config" "agent 専用の worktrunk config を渡す"
assert_contains "$log" "worktrunk/agent.toml" "agent 専用 config のパス"
assert_not_contains "$log" "--no-hooks" "pre-start は走らせる（.env コピーと依存インストール）"
assert_contains "$out" '"path":"/wt/sdd-t-1"' "作成結果のパスを返す"

# 再開: 既存ブランチは --create せずに再利用する。
: > "$FAKE_LOG"
out="$(run_js "console.log(JSON.stringify(w.openTaskWorktree({repoRoot:'$REPO_ROOT', branch:'sdd/t-1'})))")"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "wt switch sdd/t-1" "既存ブランチを開く"
assert_not_contains "$log" "--create" "既存ブランチに --create を付けない"
assert_not_contains "$log" "--base" "既存ブランチに --base を付けない"
assert_contains "$out" '"path":"/wt/sdd-t-1"' "再利用結果のパスを返す"

# 削除: worktree だけ消し、ブランチ削除は git に任せる。
: > "$FAKE_LOG"
run_js "w.removeTaskWorktree({repoRoot:'$REPO_ROOT', branch:'sdd/t-1'})"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "wt remove sdd/t-1" "ブランチ名で削除する"
assert_contains "$log" "--no-delete-branch" "ブランチ削除は wt に任せない（default branch 基準のため）"
assert_contains "$log" "--foreground" "背景実行にしない（完了を確定する）"
assert_not_contains "$log" "--force" "dirty なら止める"

# マージ: --no-ff で feature branch に入れる。
: > "$FAKE_LOG"
out="$(run_js "console.log(JSON.stringify(w.mergeTaskBranch({repoRoot:'$REPO_ROOT', branch:'sdd/t-1'})))")"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "git -C $REPO_ROOT merge --no-ff --no-edit sdd/t-1" "--no-ff でマージする"
assert_contains "$out" '"conflicted":false' "衝突しなければ false"

# 衝突は例外にせず conflicted で返す。自動で解消しない。
: > "$FAKE_LOG"
out="$(FAKE_MERGE_CONFLICT=1 run_js "console.log(JSON.stringify(w.mergeTaskBranch({repoRoot:'$REPO_ROOT', branch:'sdd/t-1'})))")"
assert_contains "$out" '"conflicted":true' "衝突は conflicted で返す"

# ブランチ削除は -d（マージ済みでなければ失敗する）。
: > "$FAKE_LOG"
run_js "w.deleteTaskBranch({repoRoot:'$REPO_ROOT', branch:'sdd/t-1'})"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "git -C $REPO_ROOT branch -d sdd/t-1" "ブランチ削除は -d を使う"
assert_not_contains "$log" "branch -D" "-D は使わない"

printf "SUMMARY %d %d\n" "$TESTS_RUN" "$TESTS_FAILED"
