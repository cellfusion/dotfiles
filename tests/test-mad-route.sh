#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/route.json"
output="$tmp/metrics/route-decisions.jsonl"

cat > "$record" <<'JSON'
{
  "version": 1,
  "type": "mad-route-decision",
  "routeId": "route-1",
  "recordedAt": "2026-09-20T08:00:00.000Z",
  "route": "single",
  "workClass": "routine",
  "complexity": "routine",
  "role": "implementer",
  "confidence": "high",
  "reasonCode": "single_task_low_parallelism",
  "backend": "omp-internal",
  "provider": "openai-codex",
  "model": "openai-codex/gpt-5.6-luna",
  "effort": "xhigh",
  "delegated": true
}
JSON
chmod 600 "$record"
recorder="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-route-record"
summary="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-route-summary"

status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  bash -c '"$1" --record "$2" --output "$3"' _ "$recorder" "$record" "$output" || status=$?
assert_eq "$status" 0 '有効な route decision を記録できる'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 'route JSONL に一行追加する'
assert_eq "$(stat -f '%Lp' "$output")" 600 'route log を mode 0600 で作る'
assert_eq "$(jq -r '.route' "$output")" single 'route を保持する'
assert_eq "$(jq -r '.model' "$output")" 'openai-codex/gpt-5.6-luna' '選択 model を保持する'

summary_out="$(MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$summary" --input "$output")"
assert_eq "$(printf '%s' "$summary_out" | jq -r '.records')" 1 'route summary が件数を返す'
assert_eq "$(printf '%s' "$summary_out" | jq -r '.routes.single')" 1 'route summary が route 別件数を返す'
assert_eq "$(printf '%s' "$summary_out" | jq -r '.models[0].model')" 'openai-codex/gpt-5.6-luna' 'route summary が model 別集計を返す'

bad="$tmp/bad.json"
jq '.route = "invalid"' "$record" > "$bad"
chmod 600 "$bad"
status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  bash -c '"$1" --record "$2" --output "$3"' _ "$recorder" "$bad" "$output" >/dev/null 2>&1 || status=$?
assert_eq "$status" 2 '不正な route を拒否する'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 '拒否時に route log を追記しない'

# Persisted history remains readable, but retired backends cannot write new records.
legacy="$tmp/legacy.json"
jq '.backend = "paseo-cli" | .routeId = "legacy-route" | .route = "delivery" | .model = "historic-model"' \
  "$record" > "$legacy"
chmod 600 "$legacy"
status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$recorder" --record "$legacy" --output "$output" >/dev/null 2>&1 || status=$?
assert_eq "$status" 2 '退役 backend の新規記録を拒否する'
jq -c . "$legacy" >> "$output"
status=0
summary_out="$(MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$summary" --input "$output" 2>&1)" || status=$?
assert_eq "$status" 0 '既存の退役 backend 履歴と新しい OMP 記録を一緒に集計できる'
if [ "$status" -eq 0 ]; then
  assert_eq "$(printf '%s' "$summary_out" | jq -r '.records')" 2 '履歴と新規記録の両方を数える'
  assert_eq "$(printf '%s' "$summary_out" | jq -r '.routes.delivery')" 1 '過去の delivery 記録を保持する'
fi

assert_summary
