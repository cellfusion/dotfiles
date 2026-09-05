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

out="$(bash "$VALIDATOR" "$RUN" 2>&1)"
status=$?
assert_eq "$status" "0" "validator: 分離された run と attempt を受け入れる"
assert_contains "$out" "valid manual orchestration run" "validator: 成功した run を報告する"
assert_eq "$(cat "$RUN/nodes/research-1/attempts/attempt-001/result.md")" "first result" \
  "validator: 先行 attempt の成果物を保持する"

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
