#!/usr/bin/env bash
# task-brief の切り出し、private mode、引数・エラー契約を検証する。
set -u

TESTS_FAILED=0
TESTS_RUN=0

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

pass() {
  printf '  ok: %s\n' "$1"
}

assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    pass "$3"
  else
    fail "$3 (expected: $2 / actual: $1)"
  fi
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 (missing: $2)" ;;
  esac
}

assert_not_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) fail "$3 (unexpected: $2)" ;;
    *) pass "$3" ;;
  esac
}

run_task_brief() {
  local plan_file="$1"
  local task_number="$2"
  local out_file="$3"
  "$task_brief" "$plan_file" "$task_number" "$out_file" >"$stdout" 2>"$stderr"
}

task_brief="$(cd "$(dirname "$0")/.." && pwd)/private_dot_agents/skills/multi-agent-development/scripts/executable_task-brief"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
plan="$tmp/plan.md"
out="$tmp/brief.md"
stdout="$tmp/stdout"
stderr="$tmp/stderr"

cat > "$plan" <<'PLAN'
# Example plan

### Task 1: ignored task

This task must not be copied.

```markdown
### Task 99: fenced heading

Task 99 must not be interpreted as a boundary.
```

### Task 2: selected task

target task body
The selected task continues after the fenced example.

### Task 3: following task

This task must not be copied.
PLAN

status=0
run_task_brief "$plan" 2 "$out" || status=$?
assert_eq "$status" 0 '指定 task の切り出しが成功する'
assert_contains "$(cat "$out" 2>/dev/null || true)" 'target task body' '指定 task を切り出す'
assert_not_contains "$(cat "$out" 2>/dev/null || true)" 'Task 99' 'code fence 内の見出しを無視する'
assert_not_contains "$(cat "$out" 2>/dev/null || true)" 'following task' '次の task を含めない'
assert_eq "$(stat -f '%Lp' "$out" 2>/dev/null || true)" 600 'brief は private mode である'
assert_eq "$(cat "$stdout" 2>/dev/null || true)" "wrote $out: $(wc -l < "$out" 2>/dev/null | tr -d ' ') lines" '成功 stdout は完全一致する'
assert_eq "$(wc -l < "$stdout" 2>/dev/null | tr -d ' ')" 1 '成功 stdout は1行だけである'
assert_eq "$(cat "$stderr" 2>/dev/null || true)" '' '成功 stderr は空である'
if test -x "$task_brief"; then
  pass 'source file は実行可能である'
else
  fail 'source file は実行可能である'
fi
TESTS_RUN=$((TESTS_RUN + 1))

status=0
"$task_brief" "$plan" 2>/dev/null || status=$?
assert_eq "$status" 2 '引数不足は exit 2 である'

missing_out="$tmp/missing.md"
status=0
"$task_brief" "$plan" 99 "$missing_out" >"$stdout" 2>"$stderr" || status=$?
assert_eq "$status" 3 '存在しない task は exit 3 である'
if test ! -e "$missing_out"; then
  pass '存在しない task は出力先を残さない'
else
  fail '存在しない task は出力先を残さない'
fi
TESTS_RUN=$((TESTS_RUN + 1))

status=0
"$task_brief" "$tmp/no-plan.md" 2 "$tmp/no-plan-out.md" >"$stdout" 2>"$stderr" || status=$?
assert_eq "$status" 2 '存在しない plan は exit 2 である'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
