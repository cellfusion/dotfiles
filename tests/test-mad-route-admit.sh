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

# The router's direct packet uses null role; admission must preserve it.
jq '.route = "direct" | .role = null' "$packet" > "$tmp/direct.json"
chmod 600 "$tmp/direct.json"
status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$admit" --packet "$tmp/direct.json" --output "$tmp/direct-admitted.json" --route-record "$route_log" >/dev/null || status=$?
assert_eq "$status" 0 'direct packet with null role is admitted'
if [ -f "$tmp/direct-admitted.json" ]; then
  assert_eq "$(jq -r '.role | type' "$tmp/direct-admitted.json")" null 'direct admitted packet preserves null role'
fi
assert_eq "$(wc -l < "$route_log" | tr -d ' ')" 2 'direct decision is recorded'
assert_eq "$(tail -1 "$route_log" | jq -r '.delegated')" false 'direct decision is not delegated'

jq '.role = null' "$packet" > "$tmp/invalid-single.json"
chmod 600 "$tmp/invalid-single.json"
status=0
MAD_ROUTE_SHARE_DIR="$root/private_dot_local/private_share/agent-config" \
  "$admit" --packet "$tmp/invalid-single.json" --output "$tmp/invalid-admitted.json" --route-record "$route_log" >/dev/null 2>&1 || status=$?
assert_eq "$status" 2 'single packet with null role is rejected'
assert_eq "$(wc -l < "$route_log" | tr -d ' ')" 2 'rejected packet is not recorded'

skill="$root/.chezmoitemplates/agent-skills/task-routing/SKILL.md"
assert_contains "$(< "$skill")" 'MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"' \
  'routing initializes MAD_SCRIPTS before recorder'
assert_contains "$(< "$skill")" 'single-cli.json` for `paseo-cli`' 'routing reads default CLI request'
assert_contains "$(< "$skill")" 'Record every decision made by task-routing' 'audit excludes skipped routing'
assert_eq "$(jq -r '.then.properties.role.type' "$root/.chezmoitemplates/agent-defs/schemas/intake-router.json")" null \
  'router schema requires null role for direct'
assert_eq "$(jq -r '.else.properties.role.enum | join(",")' "$root/.chezmoitemplates/agent-defs/schemas/intake-router.json")" \
  'implementer,architectural-implementer' 'router schema requires delegated role'

assert_summary
