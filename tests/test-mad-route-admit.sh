#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
packet="$tmp/packet.json"
admitted="$tmp/admitted.json"
route_log="$tmp/route-decisions.jsonl"

cat > "$packet" <<'JSON'
{
  "route": "single",
  "workClass": "routine",
  "role": "implementer",
  "complexity": "routine",
  "goal": "Apply a local change",
  "writeScope": ["src/example.ts"],
  "acceptanceCriteria": ["The behavior is present"],
  "verification": ["npm test"],
  "needsBrainstorming": false,
  "needsUserDecision": false,
  "confidence": "high",
  "reason": "single task with low parallelism"
}
JSON
chmod 600 "$packet"
admit="$root/private_dot_agents/skills/task-routing/scripts/executable_mad-route-admit"

status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$admit" --packet "$packet" --output "$admitted" --route-record "$route_log" \
  --backend paseo-cli --provider pi --model openai-codex/gpt-5.6-luna --effort xhigh >/dev/null || status=$?
assert_eq "$status" 0 'route admission が packet を受け付ける'
assert_eq "$(jq -r '.routeId | type' "$admitted")" string 'admitted packet に routeId を付ける'
assert_eq "$(jq -r '.route' "$admitted")" single 'admitted packet の route を保持する'
assert_eq "$(wc -l < "$route_log" | tr -d ' ')" 1 'admission が route log を一件記録する'
assert_eq "$(jq -r '.routeId' "$route_log")" "$(jq -r '.routeId' "$admitted")" 'packet と route log の routeId が一致する'
assert_eq "$(jq -r '.delegated' "$route_log")" true 'single route を delegated と記録する'

assert_summary
