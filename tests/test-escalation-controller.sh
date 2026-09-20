#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
controller="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-escalation-controller"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_judge() {
  local file="$1" action="$2" level="$3" work_class="$4" role="$5"
  jq -cn --arg action "$action" --arg workClass "$work_class" --arg targetRole "$role" \
    --arg reason 'test evidence' --arg confidence high --argjson recommendedLevel "$level" \
    '{action:$action,workClass:$workClass,targetRole:$targetRole,recommendedLevel:$recommendedLevel,reason:$reason,confidence:$confidence,evidence:["test evidence"]}' > "$file"
}

judge="$tmp/judge.json"
make_judge "$judge" increase_effort 1 routine implementer
result="$(bash "$controller" --judge-result "$judge" --current-level 0 --max-level 2 \
  --current-work-class routine --current-role implementer)"
assert_eq "$result" '{"version":1,"type":"mad-escalation-decision","status":"dispatch","action":"increase_effort","nextLevel":1,"attemptLevel":1,"workClass":"routine","role":"implementer","complexity":"routine","provenance":"mad-fix","reason":"test evidence","confidence":"high"}' 'controller emits deterministic dispatch decision'

make_judge "$judge" change_model 2 mechanical implementer
status=0
bash "$controller" --judge-result "$judge" --current-level 0 --max-level 2 \
  --current-work-class integration --current-role implementer >/dev/null 2>&1 || status=$?
assert_eq "$status" 2 'controller rejects work class downgrade'

make_judge "$judge" ask_user 0 routine implementer
result="$(bash "$controller" --judge-result "$judge" --current-level 1 --max-level 2 \
  --current-work-class routine --current-role implementer)"
assert_eq "$result" '{"version":1,"type":"mad-escalation-decision","status":"waiting_for_user","action":"ask_user","nextLevel":null,"attemptLevel":null,"workClass":"routine","role":null,"complexity":null,"provenance":null,"reason":"test evidence","confidence":"high"}' 'controller emits bounded user decision'

assert_summary
