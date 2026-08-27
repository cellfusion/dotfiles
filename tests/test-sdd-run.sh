#!/usr/bin/env bash
# fake の sdd-task / task-waves / task-brief / wt / git を挟み、driver の規律を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPTS="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/ws"

cat > "$TMP/plan.md" <<'PLAN'
# テスト用プラン

## Global Constraints

- 常体で書く

## Task 1: 一本目

**Depends on:** なし

## Task 2: 二本目

**Depends on:** なし

## Task 3: 三本目

**Depends on:** Task 1, Task 2
PLAN

# fake の sdd-task。タスク番号ごとの結果をシナリオで与える。
cat > "$TMP/bin/sdd-task" <<'FAKE'
#!/usr/bin/env bash
printf 'sdd-task %s\n' "$*" >> "$FAKE_LOG"
n=""
prev=""
for a in "$@"; do [ "$prev" = "--task" ] && n="$a"; prev="$a"; done
eval "st=\${FAKE_TASK_$n:-COMPLETE}"
printf '{ "status": "%s", "task": %s, "rounds": 0, "head": "head%s", "commits": ["c%s feat: x"], "minor": [], "outOfScope": [], "cannotVerify": [], "open": [], "concerns": "" }\n' \
  "$st" "$n" "$n" "$n"
FAKE

cat > "$TMP/bin/task-waves" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_WAVES:-wave 1: 1 2
wave 2: 3}"
exit "${FAKE_WAVES_EXIT:-0}"
FAKE

cat > "$TMP/bin/task-brief" <<'FAKE'
#!/usr/bin/env bash
printf 'task-brief %s\n' "$*" >> "$FAKE_LOG"
printf 'wrote %s: 3 lines\n' "$3"
: > "$3"
FAKE

cat > "$TMP/bin/sdd-workspace" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$SDD_TEST_WS"
FAKE

cat > "$TMP/bin/wt" <<'FAKE'
#!/usr/bin/env bash
printf 'wt %s\n' "$*" >> "$FAKE_LOG"
case "$1" in
  switch) printf '{"action":"created","branch":"b","path":"%s/wt"}\n' "$SDD_TEST_WS" ;;
  remove) printf '{"action":"removed"}\n' ;;
esac
FAKE

cat > "$TMP/bin/git" <<'FAKE'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$FAKE_LOG"
case "$*" in
  *"rev-parse --show-toplevel"*) printf '%s\n' "$FAKE_REPO_ROOT" ;;
  *"rev-parse HEAD"*) printf 'base0\n' ;;
  *"status --porcelain"*) printf '%s' "${FAKE_PORCELAIN:-}" ;;
  *merge*) [ -n "${FAKE_CONFLICT:-}" ] && { printf 'CONFLICT\n' >&2; exit 1; } ;;
  *) : ;;
esac
exit 0
FAKE

# agent-route は node で起動されるので node スクリプトにする。
# 役ごとに engine を変えられるようにする。昇格先だけが claude の routing を再現するため。
cat > "$TMP/bin/agent-route" <<'FAKE'
#!/usr/bin/env node
const role = process.argv[2]
const fallback = process.env.FAKE_ENGINE || 'codex'
const e = role === 'sdd-implementer-think'
  ? (process.env.FAKE_ENGINE_THINK || fallback)
  : fallback
console.log(`engine=${e} model=m effort=high access=write sandbox=workspace-write`)
FAKE

chmod +x "$TMP/bin"/*
export FAKE_LOG="$TMP/calls.log"
export PATH="$TMP/bin:$PATH"
export SDD_TEST_WS="$TMP/ws"
export FAKE_REPO_ROOT="$TMP/repo"

run_run() {
  : > "$FAKE_LOG"
  [ -z "${KEEP_WS:-}" ] && rm -rf "$TMP/ws"/*
  SDD_SCRIPTS_DIR="$TMP/bin" AGENT_ROUTE_BIN="$TMP/bin/agent-route" \
  SDD_REGISTRY_MODULE="$SCRIPTS/executable_run-registry" \
  SDD_WORKTREE_MODULE="$SCRIPTS/executable_task-worktree" \
    node "$SCRIPTS/executable_sdd-run" --plan "$TMP/plan.md" "$@"
}

# -- 接頭辞のない引数は実行前に BAD_ARGS にする。
out="$(run_run nope value 2>/dev/null)"
assert_contains "$out" '"status": "BAD_ARGS"' "不正な引数形式は BAD_ARGS"

# 全タスクが完了すれば COMPLETE。
out="$(run_run)"
assert_contains "$out" '"status": "COMPLETE"' "全部完了なら COMPLETE"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "sdd-task --plan $TMP/plan.md --task 1" "タスク 1 を回す"
assert_contains "$log" "sdd-task --plan $TMP/plan.md --task 3" "タスク 3 を回す"

# 2 タスクの波は worktree を切る。1 タスクの波は切らない。
assert_contains "$log" "wt switch --create" "2 タスクの波は worktree を作る"
wt_count="$(grep -c 'wt switch --create' "$FAKE_LOG")"
assert_eq "$wt_count" "2" "worktree は同時に書くタスクのぶんだけ作る（波 2 は 1 タスクなので作らない）"

# worktree を作った波はマージして片付ける。
assert_contains "$log" "git -C $TMP/repo merge --no-ff" "波を閉じるときにマージする"
assert_contains "$log" "wt remove" "マージしたら worktree を片付ける"
assert_contains "$log" "branch -d" "ブランチ削除は git に任せる"

# ledger に波とタスクの行が残る。
ledger="$(cat "$TMP/ws"/*/progress.md)"
assert_contains "$ledger" "Task 1: complete" "ledger にタスクの完了行を書く"
assert_contains "$ledger" "Wave 1:" "ledger に波の行を書く"

# 依存グラフが壊れていたら実行前に止まる。
out="$(FAKE_WAVES_EXIT=3 run_run)"
assert_contains "$out" '"status": "BAD_PLAN"' "依存グラフが壊れていたら BAD_PLAN"
assert_not_contains "$(cat "$FAKE_LOG")" "sdd-task" "BAD_PLAN ではタスクを起動しない"

# 人の判断が要る status は NEEDS_ATTENTION で返し、後続の波へ進まない。
out="$(FAKE_TASK_1=CAP_REACHED run_run)"
assert_contains "$out" '"status": "NEEDS_ATTENTION"' "CAP_REACHED は人に返す"
assert_contains "$out" '"task": 1' "どのタスクかを返す"
assert_not_contains "$(cat "$FAKE_LOG")" "--task 3" "波を閉じずに次の波へ進まない"

# 失敗したタスクの worktree は残す。
assert_not_contains "$(cat "$FAKE_LOG")" "wt remove" "失敗した波では worktree を片付けない"

# マージが衝突したら止める。自分で解消しない。
out="$(FAKE_CONFLICT=1 run_run)"
assert_contains "$out" '"status": "CONFLICT"' "マージ衝突は CONFLICT で返す"
assert_not_contains "$(cat "$FAKE_LOG")" "merge --abort" "自動で解消も中断もしない"

# claude の write 役は 1 タスクの波でも worktree を切る（書き込み範囲を縛るフラグが無い）。
out="$(FAKE_ENGINE=claude FAKE_WAVES='wave 1: 1' run_run)"
assert_contains "$(cat "$FAKE_LOG")" "wt switch --create" "claude の write 役は単独波でも worktree を切る"

# 昇格先の sdd-implementer-think だけが claude でも隔離する（既定の routing がこの形）。
out="$(FAKE_ENGINE_THINK=claude FAKE_WAVES='wave 1: 1' run_run)"
assert_contains "$(cat "$FAKE_LOG")" "wt switch --create" "昇格先だけが claude でも単独波で worktree を切る"

# feature worktree が dirty なら単独波でも worktree を切る。
out="$(FAKE_WAVES='wave 1: 1' FAKE_PORCELAIN=' M x.txt' run_run)"
assert_contains "$(cat "$FAKE_LOG")" "wt switch --create" "dirty なら単独波でも worktree を切る"

# 再開: 完了済みタスクを再 dispatch しない。
first="$(run_run)"
rid="$(printf '%s' "$first" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).runId))')"
out="$(KEEP_WS=1 run_run --run-id "$rid")"
assert_not_contains "$(cat "$FAKE_LOG")" "--task 1" "再開時に完了済みタスクを再 dispatch しない"

# 部分失敗からの再開: 成功済み task 1 の branch も task 2 とともに merge する。
first="$(FAKE_TASK_2=CAP_REACHED run_run)"
rid="$(printf '%s' "$first" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).runId))')"
out="$(KEEP_WS=1 run_run --run-id "$rid")"
assert_contains "$out" '"status": "COMPLETE"' "部分失敗から再開して COMPLETE"
log="$(cat "$FAKE_LOG")"
assert_contains "$log" "git -C $TMP/repo merge --no-ff --no-edit sdd/plan/$rid/task-1" "再開時に成功済み task 1 を merge する"
assert_not_contains "$log" "sdd-task --plan $TMP/plan.md --task 1" "部分失敗の再開で task 1 を再 dispatch しない"
assert_contains "$log" "wt switch sdd/plan/$rid/task-2" "失敗 task の worktree を再利用する"

# sdd-task に herdr の workspace を渡さない。headless の子プロセスに端末の概念は無い。
src="$(cat "$SCRIPTS/executable_sdd-run")"
assert_not_contains "$src" "'--workspace'" "sdd-run: sdd-task に --workspace を渡さない"
assert_not_contains "$src" "implementerIsTui" "sdd-run: TUI 由来の名前を残さない"
assert_contains "$src" "implementerNeedsIsolation" "sdd-run: 隔離が要るかで名前を付ける"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
