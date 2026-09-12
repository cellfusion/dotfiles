#!/usr/bin/env bash
# Paseo MAD plan の task dependency と波ごとの file collision を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

PLAN_VALIDATE="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-plan-dependency-validate"
FIXTURES="$CHEZMOI_SOURCE/tests/fixtures/agent-config/mad/plans"

node "$PLAN_VALIDATE" "$FIXTURES/valid-plan.md" >/dev/null
assert_eq "$?" "0" "plan validator: 正しい plan は exit 0"
for bad in cycle-plan missing-task-plan file-collision-plan; do
  out="$(node "$PLAN_VALIDATE" "$FIXTURES/$bad.md" 2>/dev/null)"
  assert_eq "$?" "2" "plan validator: $bad は exit 2"
  assert_eq "$out" "" "plan validator: $bad は stdout を出さない"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
