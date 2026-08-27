#!/usr/bin/env bash
# run registry が状態を原子的に持ち、プロセスの生死を素性込みで判定することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts/executable_run-registry"

TMP="$(mktemp -d)"
LIVE_PID=''
trap 'if [ -n "$LIVE_PID" ]; then kill "$LIVE_PID" 2>/dev/null || true; wait "$LIVE_PID" 2>/dev/null || true; fi; rm -rf "$TMP"' EXIT

# sandbox では ps の起動が禁止されるため、同じ引数契約の fake を使う。
# 実環境では実際の ps を使う。
NODE_COMMAND="$(node -p 'process.argv[0]')"
NODE_PATH="$(command -v node)"
if ! ps -o command= -p $$ >/dev/null 2>&1; then
  mkdir "$TMP/bin"
  printf '#!/usr/bin/env bash\ncase "$2" in lstart=,command=) printf "%%s %%s\\n" "$FAKE_PS_START" "$FAKE_PS_COMMAND" ;; command=) printf "%%s\\n" "$FAKE_PS_COMMAND" ;; lstart=) printf "%%s\\n" "$FAKE_PS_START" ;; esac\n' > "$TMP/bin/ps"
  chmod +x "$TMP/bin/ps"
  export PATH="$TMP/bin:$PATH"
fi

run_js() { node -e "const r = require('$SCRIPT'); $1"; }

# run ID は時刻と乱数の組。同じ秒でも衝突しない。
a="$(run_js "console.log(r.newRunId())")"
b="$(run_js "console.log(r.newRunId())")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$a" != "$b" ]; then _pass "newRunId: 呼ぶたびに違う"; else _fail "newRunId: 呼ぶたびに違う" "同じ値だった"; fi
case "$a" in
  2*T*-*) TESTS_RUN=$((TESTS_RUN + 1)); _pass "newRunId: 時刻と乱数の形式" ;;
  *) TESTS_RUN=$((TESTS_RUN + 1)); _fail "newRunId: 時刻と乱数の形式" "実際: $a" ;;
esac

# createRun は 0700 のディレクトリを作り、run.json を置く。
out="$(run_js "console.log(JSON.stringify(r.createRun({workspace:'$TMP/ws', plan:'/p/plan.md', runId:'RID'})))")"
assert_contains "$out" "$TMP/ws/RID" "createRun: run ディレクトリを返す"
TESTS_RUN=$((TESTS_RUN + 1))
mode="$(stat -f '%Lp' "$TMP/ws/RID")"
if [ "$mode" = "700" ]; then _pass "createRun: 0700 で作る"; else _fail "createRun: 0700 で作る" "実際: $mode"; fi
TESTS_RUN=$((TESTS_RUN + 1))
tasks_mode="$(stat -f '%Lp' "$TMP/ws/RID/tasks")"
if [ "$tasks_mode" = "700" ]; then _pass "createRun: tasks ディレクトリを 0700 で作る"; else _fail "createRun: tasks ディレクトリを 0700 で作る" "実際: $tasks_mode"; fi
assert_contains "$(cat "$TMP/ws/RID/run.json")" '"plan": "/p/plan.md"' "createRun: plan を記録する"

# updateTask は tmp + rename で書き、updatedAt を打つ。
RP="$TMP/ws/RID/run.json"
node -e "setInterval(() => {}, 1000)" &
LIVE_PID=$!
export FAKE_PS_COMMAND="$NODE_COMMAND"
export FAKE_PS_START="Thu Jan  1 00:00:00 1970"
run_js "r.updateTask('$RP', 3, {state:'RUNNING', pid: $LIVE_PID, command: '$NODE_COMMAND'})"
out="$(cat "$TMP/ws/RID/tasks/3.json")"
assert_contains "$out" '"state": "RUNNING"' "updateTask: state を書く"
assert_contains "$out" '"updatedAt"' "updateTask: updatedAt を打つ"
run_js "r.updateTask('$RP', 3, {state:'RUNNING', pid: $LIVE_PID, command: '$NODE_COMMAND', startedAt:'古い開始時刻'})"
run_js "r.updateTask('$RP', 3, {state:'RUNNING', pid: process.pid, command: 'node'})"
new_started_at="$(run_js "console.log(r.loadRun('$RP').tasks['3'].startedAt)")"
assert_not_contains "$new_started_at" "古い開始時刻" "updateTask: PID が変われば startedAt を更新する"
run_js "r.updateTask('$RP', 3, {state:'SUCCEEDED'})"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(ls "$TMP/ws/RID"/*.tmp 2>/dev/null)" ]; then _pass "updateTask: 一時ファイルを残さない"; else _fail "updateTask: 一時ファイルを残さない" "tmp が残っている"; fi
assert_contains "$(cat "$TMP/ws/RID/tasks/3.json")" '"state": "SUCCEEDED"' "updateTask: タスク別ファイルに書く"
TESTS_RUN=$((TESTS_RUN + 1))
task_mode="$(stat -f '%Lp' "$TMP/ws/RID/tasks/3.json")"
if [ "$task_mode" = "600" ]; then _pass "updateTask: タスク別ファイルを 0600 で作る"; else _fail "updateTask: タスク別ファイルを 0600 で作る" "実際: $task_mode"; fi

# 許される state の集合を持つ。
states="$(run_js "console.log(r.STATES.join(','))")"
for s in PREPARING RUNNING CANCEL_REQUESTED SUCCEEDED FAILED CANCELLED ORPHANED; do
  assert_contains "$states" "$s" "STATES: $s を持つ"
done

# 承認待ちの state は持たない。headless には承認を求める相手がいない。
for s in WAITING_TRUST WAITING_APPROVAL; do
  assert_not_contains "$states" "$s" "STATES: $s を持たない"
done

# isAlive: PATH 経由の node でも true。
out="$(run_js "
  r.updateTask('$RP', 5, {state:'RUNNING', pid: process.pid, command: 'node'})
  const e = r.taskEntry(r.loadRun('$RP'), 5)
  console.log(String(r.isAlive(e)))
")"
assert_eq "$out" "true" "isAlive: node で起動した生きているプロセスは true"

# isAlive: node の絶対パス起動でも true。
out="$("$NODE_PATH" -e "
  const r = require('$SCRIPT')
  r.updateTask('$RP', 6, {state:'RUNNING', pid: process.pid, command: '$NODE_PATH'})
  const e = r.taskEntry(r.loadRun('$RP'), 6)
  console.log(String(r.isAlive(e)))
")"
assert_eq "$out" "true" "isAlive: 絶対パスで起動した生きているプロセスは true"
run_js "r.updateTask('$RP', 5, {state:'SUCCEEDED'}); r.updateTask('$RP', 6, {state:'SUCCEEDED'})"

# isAlive: command の basename が違えば false。
out="$(run_js "console.log(String(r.isAlive({ pid: process.pid, command: '/bin/sh', startedAt: '$FAKE_PS_START' })))")"
assert_eq "$out" "false" "isAlive: command basename が違えば false"

# isAlive: 生きていても開始時刻が違えば false（PID 再利用を誤認しない）。
out="$(run_js "console.log(String(r.isAlive({ pid: process.pid, command: 'node', startedAt: '別の開始時刻' })))")"
assert_eq "$out" "false" "isAlive: 開始時刻が違えば false"

# isAlive: 存在しない pid は false。
out="$(run_js "console.log(String(r.isAlive({ pid: 999999, command: '/bin/sh', startedAt: '$FAKE_PS_START' })))")"
assert_eq "$out" "false" "isAlive: 死んだ pid は false"

# reap: RUNNING なのに生きていないタスクを ORPHANED にする。
run_js "r.updateTask('$RP', 3, {state:'RUNNING', pid: $LIVE_PID, command: '$NODE_COMMAND'})"
run_js "r.updateTask('$RP', 4, {state:'RUNNING', pid: 999999, command: '/bin/sh'})"
out="$(run_js "console.log(JSON.stringify(r.reap('$RP')))" )"
assert_contains "$out" '"orphaned":[4]' "reap: 死んだ RUNNING を ORPHANED にする"
assert_contains "$(run_js "console.log(JSON.stringify(r.loadRun('$RP')))" )" '"ORPHANED"' "reap: state を書き換える"
assert_contains "$(run_js "console.log(JSON.stringify(r.loadRun('$RP')))" )" '"RUNNING"' "reap: 生きている RUNNING は触らない"

# 別タスクへの並行書き込みで状態を失わない。
PARALLEL_N=12
READY_DIR="$TMP/parallel-ready"
mkdir "$READY_DIR"
parallel_pids=()
for n in $(seq 1 "$PARALLEL_N"); do
  node -e "
    const fs = require('node:fs')
    const r = require('$SCRIPT')
    const ready = '$READY_DIR/$n'
    fs.writeFileSync(ready, '')
    while (fs.readdirSync('$READY_DIR').length < $PARALLEL_N) {}
    r.updateTask('$RP', $n, {state: 'SUCCEEDED', marker: 'task-$n'})
  " &
  parallel_pids+=("$!")
done
parallel_failed=0
for pid in "${parallel_pids[@]}"; do
  wait "$pid" || parallel_failed=1
done
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$parallel_failed" -eq 0 ]; then _pass "updateTask: 並行子プロセスがすべて完了する"; else _fail "updateTask: 並行子プロセスがすべて完了する" "子プロセスが失敗した"; fi
parallel_tasks="$(run_js "console.log(JSON.stringify(r.loadRun('$RP').tasks))")"
for n in $(seq 1 "$PARALLEL_N"); do
  assert_contains "$parallel_tasks" '"'$n'":{"state":"SUCCEEDED"' "loadRun: 並行書き込み task-$n を保持する"
  assert_contains "$parallel_tasks" '"marker":"task-'"$n"'"' "loadRun: 並行書き込み marker-$n を保持する"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
