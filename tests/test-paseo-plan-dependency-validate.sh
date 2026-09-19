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

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

{ printf '#%s# Task 1: fixture\n\n' '##'
  printf '**Files:**\n- Modify: `a.txt`\n\n'
  printf '**Depends on:** none\n\n'
  printf '**Complexity:** unknown\n'; } > "$TMP/bad.md"
status=0
node "$PLAN_VALIDATE" "$TMP/bad.md" >/dev/null 2>&1 || status=$?
assert_eq "$status" "2" "plan validate: 未知の Complexity を拒む"

{ printf '#%s# Task 1: fixture\n\n' '##'
  printf '**Files:**\n- Modify: `a.txt`\n\n'
  printf '**Depends on:** none\n'; } > "$TMP/absent.md"
status=0
node "$PLAN_VALIDATE" "$TMP/absent.md" >/dev/null 2>&1 || status=$?
assert_eq "$status" "0" "plan validate: Complexity の行が無くても受け入れる"

write_plan() {
  { printf '#%s# Task 1: fixture\n\n' '##'
    printf '**Files:**\n- Modify: `a.txt`\n\n'
    printf '**Depends on:** none\n\n'
    printf '**%s:** %s\n' 'Complexity' "$1"; } > "$TMP/complexity.md"
}

for value in simple critical; do
  write_plan "$value"
  status=0
  err="$(node "$PLAN_VALIDATE" "$TMP/complexity.md" 2>&1 >/dev/null)" || status=$?
  assert_eq "$status" "0" "plan validate: Complexity $value は exit 0"
  assert_eq "$err" "" "plan validate: Complexity $value は stderr を出さない"
done

write_plan standard
status=0
out="$(node "$PLAN_VALIDATE" "$TMP/complexity.md" 2>"$TMP/complexity.err")" || status=$?
assert_eq "$status" "0" "plan validate: Complexity standard は exit 0"
assert_eq "$out" "" "plan validate: Complexity standard は stdout を出さない"
assert_contains "$(cat "$TMP/complexity.err")" \
  "Task 1: Complexity standard は routine へ読み替えた。simple/routine/complex/critical のいずれかに直すこと" \
  "plan validate: Complexity standard は読み替えの warning を出す"

write_plan unknown
status=0
node "$PLAN_VALIDATE" "$TMP/complexity.md" >/dev/null 2>"$TMP/complexity.err" || status=$?
assert_eq "$status" "2" "plan validate: Complexity unknown は exit 2"
assert_contains "$(cat "$TMP/complexity.err")" \
  "Task 1: Complexity が simple/routine/complex/critical でない" \
  "plan validate: Complexity unknown は error の文言を出す"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
