#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
recorder="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-outcome-record"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
record="$tmp/record.json"
output="$tmp/metrics/attempt-outcomes.jsonl"

cat > "$record" <<'JSON'
{
  "version": 1,
  "type": "mad-attempt-outcome",
  "recordedAt": "2026-09-20T08:00:00.000Z",
  "taskId": "task-1",
  "runId": "run-1",
  "attemptId": "attempt-1",
  "route": {
    "workClass": "routine",
    "complexity": "routine",
    "role": "implementer",
    "backend": "paseo-cli",
    "provider": "codex",
    "model": "gpt-5.6-luna",
    "effort": "xhigh",
    "policyLevel": 0,
    "trigger": "initial",
    "round": 0
  },
  "outcome": {
    "status": "completed",
    "retryCount": 0,
    "durationMs": 120000
  },
  "usage": {
    "inputTokens": 1000,
    "cachedInputTokens": 800,
    "outputTokens": 250,
    "costUsd": null,
    "source": "paseo-inspect"
  },
  "toolLoopCount": 4,
  "verification": {
    "tests": "passed",
    "review": "accepted",
    "changedFiles": 2,
    "regression": "none"
  }
}
JSON
chmod 600 "$record"

status=0
MAD_OUTCOME_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  bash -c '"$1" --record "$2" --output "$3"' _ "$recorder" "$record" "$output" || status=$?
assert_eq "$status" 0 '有効な outcome を記録できる'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 'JSONL に一行だけ追加する'
assert_eq "$(stat -f '%Lp' "$output")" 600 'ログを mode 0600 で作る'
assert_eq "$(jq -r '.type' "$output")" 'mad-attempt-outcome' 'type を保持する'
assert_eq "$(jq -r '.route.model' "$output")" 'gpt-5.6-luna' 'route を保持する'
assert_eq "$(jq -r '.verification.tests' "$output")" 'passed' 'verification を保持する'

bad="$tmp/bad.json"
jq 'del(.usage.inputTokens)' "$record" > "$bad"
chmod 600 "$bad"
status=0
MAD_OUTCOME_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  bash -c '"$1" --record "$2" --output "$3"' _ "$recorder" "$bad" "$output" >/dev/null 2>&1 || status=$?
assert_eq "$status" 2 '必須 usage field の欠落を拒否する'
assert_eq "$(wc -l < "$output" | tr -d ' ')" 1 '拒否時にログを追記しない'

assert_summary
