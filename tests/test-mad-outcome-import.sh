#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
runs="$tmp/runs"
run="$runs/run-1"
attempt="$run/nodes/task-1/attempts/a1"
mkdir -p "$attempt"
chmod 700 "$runs" "$run" "$run/nodes" "$run/nodes/task-1" "$attempt"

cat > "$attempt/state.json" <<'JSON'
{
  "run_id": "run-1",
  "node": "task-1",
  "attempt": "a1",
  "round": 0,
  "state": "ok",
  "started_at": "2026-09-20T08:00:00Z",
  "finished_at": "2026-09-20T08:02:00Z",
  "create_accepted": true,
  "child_ref": "child-1",
  "backend": "paseo-cli",
  "backend_reason": "test",
  "parent_decision": "accepted"
}
JSON
cat > "$attempt/launch.json" <<'JSON'
{
  "version": 1,
  "type": "mad-launch-spec",
  "status": "ok",
  "environment": "default",
  "duty": "implement",
  "complexity": "routine",
  "requestedComplexity": "routine",
  "provider": "pi",
  "model": "openai-codex/gpt-5.6-luna",
  "modeId": "auto",
  "thinkingOptionId": "xhigh",
  "features": {},
  "warnings": []
}
JSON
cat > "$attempt/execution-context.md" <<'EOF'
RUN_ID=run-1
TASK_ID=task-1
WORK_CLASS=routine
EOF
cat > "$attempt/result.json" <<'JSON'
{"changedFiles":["src/example.ts"]}
JSON
chmod 600 "$attempt"/*

legacy="$run/nodes/legacy/attempts/a1"
mkdir -p "$legacy"
chmod 700 "$run/nodes/legacy" "$legacy"
cat > "$legacy/state.json" <<'JSON'
{"run_id":"run-1","node":"legacy","attempt":"a2","round":0,"state":"ok","started_at":"2026-09-20T08:00:00Z","finished_at":"2026-09-20T08:01:00Z","create_accepted":true,"backend":"paseo-cli"}
JSON
cat > "$legacy/launch.json" <<'JSON'
{"version":1,"type":"mad-launch-spec","status":"ok","provider":"codex","model":"gpt-5.6-luna","thinkingOptionId":"max"}
JSON
chmod 600 "$legacy"/*

output="$tmp/attempt-outcomes.jsonl"
importer="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-outcome-import"
set +e
result="$(MAD_OUTCOME_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$importer" --runs-dir "$runs" --output "$output")"
status=$?
set -e
assert_eq "$status" 0 '有効な run artifact を import できる'
assert_eq "$(printf '%s' "$result" | jq -r .recorded)" 1 '一件の outcome を記録する'
assert_eq "$(printf '%s' "$result" | jq -r .skipped)" 1 'complexity 不明の旧 artifact を推測せず skip する'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 'outcome JSONL に一行追加する'
assert_eq "$(jq -r '.route.workClass' "$output")" routine 'work class を context から復元する'
assert_eq "$(jq -r '.route.model' "$output")" 'openai-codex/gpt-5.6-luna' 'launch model を復元する'
assert_eq "$(jq -r '.outcome.durationMs' "$output")" 120000 'attempt duration を復元する'
assert_not_contains "$(cat "$output")" 'src/example.ts' 'ファイル内容を outcome に保存しない'

set +e
result="$(MAD_OUTCOME_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$importer" --runs-dir "$runs" --output "$output")"
status=$?
set -e
assert_eq "$status" 0 '同じ run を二重 import しても成功する'
assert_eq "$(printf '%s' "$result" | jq -r .duplicates)" 1 '二重 import を duplicate として扱う'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 '二重 import で追記しない'

assert_summary
