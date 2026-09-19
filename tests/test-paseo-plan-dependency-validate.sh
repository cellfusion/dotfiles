#!/usr/bin/env bash
# Paseo MAD plan の dependency、wave、code fence 契約を検証する。
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

validator="$(cd "$(dirname "$0")/.." && pwd)/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-plan-dependency-validate"
fixtures="$(cd "$(dirname "$0")/.." && pwd)/tests/fixtures/agent-config/mad/plans"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/valid.md" <<'PLAN'
# Paseo MAD plan

### Task 1: prepare

**Files:**
- Create: `one.txt`

**Depends on:** none

### Task 2: implement

**Files:**
- Modify: `two.txt`

**Depends on:** Task 1

### Task 3: review

**Files:**
- Modify: `three.txt`

**Depends on:** Task 1
PLAN

status=0
out="$("$validator" "$tmp/valid.md" 2>"$tmp/valid.err")" || status=$?
assert_eq "$status" 0 '正しい plan は exit 0'
assert_eq "$out" '' '通常検証は stdout を出さない'
assert_eq "$(cat "$tmp/valid.err")" '' '正しい plan は stderr を出さない'

status=0
out="$("$validator" --waves "$tmp/valid.md" 2>"$tmp/valid-waves.err")" || status=$?
assert_eq "$status" 0 '--waves の正しい plan は exit 0'
assert_eq "$out" $'wave 1: 1\nwave 2: 2 3' '依存関係から wave を昇順で出力する'
assert_eq "$(cat "$tmp/valid-waves.err")" '' '--waves の正しい plan は stderr を出さない'

cat > "$tmp/cycle.md" <<'PLAN'
### Task 1: first

**Files:**
- Modify: `one.txt`

**Depends on:** Task 2

### Task 2: second

**Files:**
- Modify: `two.txt`

**Depends on:** Task 1
PLAN

cat > "$tmp/missing-task.md" <<'PLAN'
### Task 1: first

**Files:**
- Modify: `one.txt`

**Depends on:** none

### Task 2: second

**Files:**
- Modify: `two.txt`

**Depends on:** Task 9
PLAN

cat > "$tmp/file-collision.md" <<'PLAN'
### Task 1: first

**Files:**
- Modify: `one.txt`

**Depends on:** none

### Task 2: second

**Files:**
- Modify: `shared.txt`

**Depends on:** none

### Task 3: third

**Files:**
- Modify: `shared.txt`

**Depends on:** none
PLAN

for bad in cycle missing-task file-collision; do
  status=0
  out="$("$validator" --waves "$tmp/$bad.md" 2>"$tmp/$bad.err")" || status=$?
  assert_eq "$status" 2 "$bad は --waves でも exit 2"
  assert_eq "$out" '' "$bad は validation error 時に stdout を出さない"
done

cat > "$tmp/complexity.md" <<'PLAN'
### Task 1: fixture

**Files:**
- Modify: `a.txt`

**Depends on:** none

**Complexity:** standard
PLAN
status=0
out="$("$validator" "$tmp/complexity.md" 2>"$tmp/complexity.err")" || status=$?
assert_eq "$status" 0 'Complexity standard は exit 0'
assert_eq "$out" '' 'Complexity standard は stdout を出さない'
assert_contains "$(cat "$tmp/complexity.err")" 'Complexity standard は routine へ読み替えた' 'Complexity standard は warning を出す'

cat > "$tmp/unknown-complexity.md" <<'PLAN'
### Task 1: fixture

**Files:**
- Modify: `a.txt`

**Depends on:** none

**Complexity:** unknown
PLAN
status=0
"$validator" "$tmp/unknown-complexity.md" >"$tmp/unknown-complexity.out" 2>"$tmp/unknown-complexity.err" || status=$?
assert_eq "$status" 2 '未知の Complexity は exit 2'
assert_eq "$(cat "$tmp/unknown-complexity.out")" '' '未知の Complexity は stdout を出さない'

status=0
out="$("$validator" --waves "$fixtures/no-depends-plan.md" 2>"$tmp/no-depends.err")" || status=$?
assert_eq "$status" 0 'Depends on が無い plan は exit 0'
assert_eq "$out" $'wave 1: 1\nwave 2: 2\nwave 3: 3' '未宣言依存を直列の wave にする'
assert_eq "$(cat "$tmp/no-depends.err")" 'warning: Depends on の宣言が無いため直列とみなす' '未宣言依存の warning を1行出す'

status=0
out="$("$validator" "$fixtures/no-depends-plan.md" 2>"$tmp/no-depends-normal.err")" || status=$?
assert_eq "$status" 0 '通常検証は未宣言依存でも exit 0'
assert_eq "$out" '' '通常検証は未宣言依存でも stdout を出さない'
assert_eq "$(cat "$tmp/no-depends-normal.err")" '' '未宣言依存の warning は --waves 時だけ出す'

status=0
out="$("$validator" --waves "$fixtures/reordered-no-depends-plan.md" 2>"$tmp/reordered.err")" || status=$?
assert_eq "$status" 0 '記載順が異なる未宣言依存 plan は exit 0'
assert_eq "$out" $'wave 1: 1\nwave 2: 2\nwave 3: 3' '未宣言依存は Task 番号基準で wave を決める'

status=0
out="$("$validator" --waves "$fixtures/explicit-none-plan.md" 2>"$tmp/explicit-none.err")" || status=$?
assert_eq "$status" 0 '明示的 none/なし plan は exit 0'
assert_eq "$out" $'wave 1: 1 2\nwave 2: 3' '明示的 none/なしを依存なしとして扱う'
assert_eq "$(cat "$tmp/explicit-none.err")" '' '明示的 none/なし plan は warning を出さない'

status=0
out="$("$validator" --waves "$fixtures/fenced-task-plan.md" 2>"$tmp/fenced.err")" || status=$?
assert_eq "$status" 0 'fence 内の Task 見出しを無視する plan は exit 0'
assert_eq "$out" $'wave 1: 1\nwave 2: 2' 'fence 内の Task 見出しを無視する'
assert_eq "$(cat "$tmp/fenced.err")" '' 'fence 内の Task 見出しを無視する plan は stderr を出さない'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
