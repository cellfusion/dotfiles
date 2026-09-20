#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

script="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_escalation-policy"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

write_judge() {
  cat > "$tmp/judge.json" <<JSON
{
  "action": "$1",
  "workClass": "$2",
  "targetRole": $3,
  "recommendedLevel": $4,
  "reason": "evidence-backed decision",
  "evidence": ["review finding"],
  "confidence": "high"
}
JSON
}

run_case() {
  local expected_status="$1"
  shift
  local output status=0
  output="$($script "$@" 2>"$tmp/stderr")" || status=$?
  assert_eq "$status" "$expected_status" "escalation policy exit status"
  printf '%s' "$output"
}

write_judge retry_same 'routine' '"implementer"' 1
output="$(run_case 0 --judge-result "$tmp/judge.json" --current-level 1 --max-level 3 --current-work-class routine --current-role implementer)"
assert_contains "$output" '"nextLevel":1' 'retry_same keeps the current level'

write_judge increase_effort 'routine' '"implementer"' 2
output="$(run_case 0 --judge-result "$tmp/judge.json" --current-level 1 --max-level 3 --current-work-class routine --current-role implementer)"
assert_contains "$output" '"nextLevel":2' 'increase_effort advances within the policy'

write_judge change_model 'architectural' '"architectural-implementer"' 3
output="$(run_case 0 --judge-result "$tmp/judge.json" --current-level 1 --max-level 3 --current-work-class routine --current-role implementer)"
assert_contains "$output" '"role":"architectural-implementer"' 'change_model can change the role'

write_judge ask_user 'integration' 'null' 2
output="$(run_case 0 --judge-result "$tmp/judge.json" --current-level 1 --max-level 3 --current-work-class routine --current-role implementer)"
assert_contains "$output" '"nextLevel":null' 'ask_user does not authorize a launch'

write_judge increase_effort 'routine' '"implementer"' 1
run_case 2 --judge-result "$tmp/judge.json" --current-level 1 --max-level 3 --current-work-class routine --current-role implementer >/dev/null

assert_summary
