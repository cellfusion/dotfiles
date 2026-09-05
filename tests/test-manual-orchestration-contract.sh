#!/usr/bin/env bash
# 手動 MAD の成果物契約を、Paseo MCP を起動せず実行可能な validator で検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

VALIDATOR="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
FIXTURE="$(mktemp -d)"
RUN="$FIXTURE/run-01"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$RUN"
printf '%s\n' '{
  "run_id": "run-01",
  "recipe": "research",
  "state": "ok",
  "current_round": 0,
  "started_at": "2026-09-05T00:00:00Z",
  "finished_at": "2026-09-05T00:01:00Z",
  "backend": "subagent",
  "backend_reason": "Paseo MCP unavailable",
  "parent_decision": "complete"
}' > "$RUN/state.json"

write_attempt() {
  local node_id="$1"
  local attempt_id="$2"
  local result="$3"
  local attempt_dir="$RUN/nodes/$node_id/attempts/$attempt_id"
  mkdir -p "$attempt_dir"
  printf '調査指示\n' > "$attempt_dir/prompt.md"
  printf '%s\n' "$result" > "$attempt_dir/result.md"
  printf 'backend log\n' > "$attempt_dir/log.md"
  printf '%s\n' "{
  \"run_id\": \"run-01\",
  \"node\": \"$node_id\",
  \"attempt\": \"$attempt_id\",
  \"round\": 0,
  \"state\": \"ok\",
  \"started_at\": \"2026-09-05T00:00:00Z\",
  \"finished_at\": \"2026-09-05T00:01:00Z\",
  \"backend\": \"subagent\",
  \"backend_reason\": \"Paseo MCP unavailable\",
  \"parent_decision\": \"accepted\"
}" > "$attempt_dir/state.json"
}

# 同一 node の再実行は attempt ごとのファイルに分離され、先行結果を上書きしない。
write_attempt research-1 attempt-001 'first result'
write_attempt research-1 attempt-002 'retry result'
write_attempt research-2 attempt-001 'constraint result'
write_attempt research-3 attempt-001 'alternative result'

out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: 分離された run と attempt を受け入れる"
assert_contains "$out" "valid manual orchestration run" "validator: 成功した run を報告する"
assert_eq "$(cat "$RUN/nodes/research-1/attempts/attempt-001/result.md")" "first result" \
  "validator: 先行 attempt の成果物を保持する"

# backend の選択は実 backend を起動せず、Paseo MCP が使える場合と使えない場合の
# 共通成果物契約として検証する。
set_backend() {
  local backend="$1"
  local reason="$2"
  local state_file
  jq --arg backend "$backend" --arg reason "$reason" \
    '.backend = $backend | .backend_reason = $reason' "$RUN/state.json" > "$RUN/state.json.tmp"
  mv "$RUN/state.json.tmp" "$RUN/state.json"
  while IFS= read -r state_file; do
    jq --arg backend "$backend" --arg reason "$reason" \
      '.backend = $backend | .backend_reason = $reason' "$state_file" > "$state_file.tmp"
    mv "$state_file.tmp" "$state_file"
  done < <(find "$RUN/nodes" -type f -name state.json -print)
}

for backend_case in "paseo-mcp:Paseo MCP available" "subagent:Paseo MCP unavailable"; do
  backend="${backend_case%%:*}"
  reason="${backend_case#*:}"
  set_backend "$backend" "$reason"
  out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
  status=$?
  assert_eq "$status" "0" "validator: $backend の共通成果物契約を受け入れる"
done

# 完了した research は既定の 3 調査 node を全て持つ。
rm -rf "$RUN/nodes/research-3"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: research の必須 3 node 欠落を拒否する"
assert_contains "$out" "research-3" "validator: 欠けた research node を示す"
write_attempt research-3 attempt-001 'alternative result'

# root を ok とした run は、failed / stopped の子を隠せない。
for child_state in failed stopped; do
  attempt_state="$RUN/nodes/research-3/attempts/attempt-001/state.json"
  jq --arg state "$child_state" '.state = $state' "$attempt_state" > "$attempt_state.tmp"
  mv "$attempt_state.tmp" "$attempt_state"
  out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
  status=$?
  assert_eq "$status" "1" "validator: root ok と $child_state child の矛盾を拒否する"
  assert_contains "$out" "root state ok" "validator: root と child の状態矛盾を示す"
  jq '.state = "ok"' "$attempt_state" > "$attempt_state.tmp"
  mv "$attempt_state.tmp" "$attempt_state"
done

# 3 調査 node が全て ok になるまで、後段の synthesis を開始できない。
jq '.state = "running"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"
attempt_state="$RUN/nodes/research-3/attempts/attempt-001/state.json"
jq '.state = "pending"' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
write_attempt synthesis attempt-001 'synthesis result'
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: 全 research child ok 前の後段を拒否する"
assert_contains "$out" "before all research nodes are ok" \
  "validator: 後段開始を拒否した理由を示す"
rm -rf "$RUN/nodes/synthesis"
jq '.state = "ok"' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
jq '.state = "ok"' "$RUN/state.json" > "$RUN/state.json.tmp"
mv "$RUN/state.json.tmp" "$RUN/state.json"

# ループ型 recipe は、max_rounds に未完了で到達した run を unresolved として残す。
LOOP_RUN="$FIXTURE/run-loop"
mkdir -p "$LOOP_RUN"
printf '%s\n' '{
  "run_id": "run-loop",
  "recipe": "refine",
  "state": "unresolved",
  "current_round": 2,
  "max_rounds": 2,
  "started_at": "2026-09-05T00:00:00Z",
  "finished_at": "2026-09-05T00:01:00Z",
  "backend": "subagent",
  "backend_reason": "Paseo MCP unavailable",
  "parent_decision": "max_rounds reached without completion"
}' > "$LOOP_RUN/state.json"
out="$(bash "$VALIDATOR" "$LOOP_RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: max_rounds 到達時の unresolved run を受け入れる"
jq '.max_rounds = 1' "$LOOP_RUN/state.json" > "$LOOP_RUN/state.json.tmp"
mv "$LOOP_RUN/state.json.tmp" "$LOOP_RUN/state.json"
out="$(bash "$VALIDATOR" "$LOOP_RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: max_rounds を超えた unresolved run を拒否する"
assert_contains "$out" "max_rounds" "validator: loop 上限違反を示す"

# attempt が state の第一級フィールドでなければ、ディレクトリだけから補完して受理しない。
attempt_state="$RUN/nodes/research-1/attempts/attempt-002/state.json"
jq 'del(.attempt)' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: attempt の欠落を拒否する"
assert_contains "$out" "attempt" "validator: 欠落した第一級フィールドを示す"

# state を欠く attempt は、後段が完了状態を確認できないため拒否する。
jq '.attempt = "attempt-002"' "$attempt_state" > "$attempt_state.tmp"
mv "$attempt_state.tmp" "$attempt_state"
incomplete_attempt="$RUN/nodes/research-1/attempts/attempt-003"
mkdir -p "$incomplete_attempt"
printf '調査指示\n' > "$incomplete_attempt/prompt.md"
printf 'incomplete result\n' > "$incomplete_attempt/result.md"
printf 'backend log\n' > "$incomplete_attempt/log.md"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: state を欠く attempt を拒否する"
assert_contains "$out" "state.json" "validator: state の欠落を示す"
rm -rf "$incomplete_attempt"

# node 固有の成果物を attempts の外へ置く旧レイアウトは、並列上書きの余地があるため拒否する。
printf 'legacy result\n' > "$RUN/nodes/research-1/result.md"
out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "1" "validator: attempts 外の node 成果物を拒否する"
assert_contains "$out" "attempts" "validator: 分離されていない成果物を示す"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
