#!/usr/bin/env bash
# manual-orchestration-validate が worktrees.json を台帳として検査することを確かめる。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

VALIDATE="$REPO_ROOT/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

BASE_SHA=1111111111111111111111111111111111111111

# run_status が ok の最小の run directory を作る。recipe は triage とし、
# implement 固有の review_policy を要求されない形にする。
mk_run() {
  local dir="$1"
  local attempt="$dir/nodes/impl-1/attempts/a1"
  mkdir -p "$attempt"
  printf 'prompt\n' > "$attempt/prompt.md"
  printf 'result\n' > "$attempt/result.md"
  printf 'log\n' > "$attempt/log.md"
  cat > "$attempt/state.json" <<'JSON'
{
  "run_id": "r1", "node": "impl-1", "attempt": "a1", "round": 0,
  "state": "ok", "phase": "implement", "phase_state": "ok", "next_action": "adopt",
  "started_at": "2026-09-19T00:00:00Z", "finished_at": "2026-09-19T00:30:00Z",
  "create_accepted": true, "child_ref": "c1",
  "backend": "paseo-mcp", "backend_reason": "only backend", "parent_decision": "none"
}
JSON
  cat > "$attempt/handoff.json" <<JSON
{"run_id":"r1","node":"impl-1","attempt":"a1","artifact_paths":["$attempt/result.md"]}
JSON
  cat > "$dir/state.json" <<JSON
{
  "run_id": "r1", "recipe": "triage", "state": "ok",
  "phase": "implement", "phase_state": "ok", "next_action": "done",
  "current_round": 0,
  "started_at": "2026-09-19T00:00:00Z", "finished_at": "2026-09-19T01:00:00Z",
  "backend": "paseo-mcp", "backend_reason": "only backend", "parent_decision": "none",
  "active_nodes": [], "completed_nodes": ["impl-1"],
  "adopted_attempts": {"impl-1": "a1"},
  "artifact_paths": ["$attempt/result.md"],
  "base": "$BASE_SHA"
}
JSON
}

mk_ledger() {
  cat > "$1/worktrees.json" <<JSON
{
  "impl-1": {
    "path": "/tmp/mad/worktrees/demo/mad-r1-impl-1",
    "branch": "mad/r1/impl-1",
    "base": "$2",
    "integration": "merged",
    "removed": $3,
    "branch_deleted": false
  }
}
JSON
}

good="$work/good"
mk_run "$good"
mk_ledger "$good" "$BASE_SHA" true
out="$(bash "$VALIDATE" "$good" 2>&1)"
assert_eq "$?" 0 'worktrees.json を持つ run は通る'
assert_contains "$out" 'valid manual orchestration run' '成功のメッセージを出す'

mismatch="$work/mismatch"
mk_run "$mismatch"
mk_ledger "$mismatch" 2222222222222222222222222222222222222222 true
out="$(bash "$VALIDATE" "$mismatch" 2>&1)"
assert_eq "$?" 1 '台帳の base が run state の base と違う run は落ちる'
assert_contains "$out" 'base' '失敗の理由に base を挙げる'

unremoved="$work/unremoved"
mk_run "$unremoved"
mk_ledger "$unremoved" "$BASE_SHA" false
out="$(bash "$VALIDATE" "$unremoved" 2>&1)"
assert_eq "$?" 1 'removed が false のまま ok にした run は落ちる'
assert_contains "$out" 'removed' '失敗の理由に removed を挙げる'

# implement の完了検査は final-review などの node を求めるので、台帳が無いことだけを
# 見るこの fixture は run を running のままにする。attempt も pending にして、
# 経過時間で警告が出る running の attempt を作らない。
required="$work/required"
mk_run "$required"
node -e '
const fs = require("node:fs")
const runFile = process.argv[1] + "/state.json"
const run = JSON.parse(fs.readFileSync(runFile, "utf8"))
Object.assign(run, {
  recipe: "implement", max_rounds: 4, state: "running", phase_state: "running",
  finished_at: null, active_nodes: ["impl-1"], completed_nodes: [],
  adopted_attempts: {}, artifact_paths: [],
})
fs.writeFileSync(runFile, JSON.stringify(run, null, 2))
const attemptFile = process.argv[1] + "/nodes/impl-1/attempts/a1/state.json"
const attempt = JSON.parse(fs.readFileSync(attemptFile, "utf8"))
Object.assign(attempt, {
  state: "pending", phase_state: "pending", next_action: "create",
  started_at: null, finished_at: null, create_accepted: false,
})
delete attempt.child_ref
fs.writeFileSync(attemptFile, JSON.stringify(attempt, null, 2))
' "$required"
out="$(bash "$VALIDATE" "$required" 2>&1)"
assert_eq "$?" 1 'implement は worktrees.json を必須にする'
assert_contains "$out" 'worktrees.json is required' '欠けた台帳の名前を挙げる'

source_text="$(cat "$VALIDATE")"
assert_not_contains "$source_text" 'workspaces.json' 'validator は workspaces.json を読まない'
assert_contains "$source_text" 'validate_worktrees' '関数名は validate_worktrees である'

assert_summary
