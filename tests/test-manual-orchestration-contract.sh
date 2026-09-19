#!/usr/bin/env bash
# implement 結果の post-commit 検査が読み取り専用で契約を守ることを検証する。
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

assert_status() {
  assert_eq "$1" "$2" "$3"
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 (missing: $2)" ;;
  esac
}

assert_one_line() {
  local file="$1"
  local label="$2"
  assert_eq "$(wc -l < "$file" | tr -d ' ')" 1 "$label"
}

root="$(cd "$(dirname "$0")/.." && pwd)"
validator="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local dir="$1"
  local subject="$2"
  local extra_commits="${3:-0}"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name 'MAD Test'
  printf 'base\n' > "$dir/base.txt"
  git -C "$dir" add base.txt
  git -c commit.gpgsign=false -C "$dir" commit -qm 'chore: create fixture'
  local base
  base="$(git -C "$dir" rev-parse HEAD)"
  printf 'implementation\n' > "$dir/changed.txt"
  git -C "$dir" add changed.txt
  git -c commit.gpgsign=false -C "$dir" commit -qm "$subject"
  if [ "$extra_commits" -gt 0 ]; then
    printf 'second implementation\n' > "$dir/second.txt"
    git -C "$dir" add second.txt
    git -c commit.gpgsign=false -C "$dir" commit -qm 'feat: add second change'
  fi
  printf '%s\n' "$base"
}

run_check() {
  local repo="$1"
  local base="$2"
  local round="$3"
  local result="$4"
  bash "$validator" --check-implement-result --workdir "$repo" --base "$base" \
    --round "$round" --result-file "$result" >"$stdout" 2>"$stderr"
}

write_result() {
  local file="$1"
  local round="$2"
  local base_head="$3"
  local changed_files="$4"
  printf '{"round":%s,"baseHead":"%s","changedFiles":%s}\n' \
    "$round" "$base_head" "$changed_files" > "$file"
}

repo="$tmp/valid-repo"
base="$(make_repo "$repo" 'feat: add implementation')"
result="$tmp/result.json"
stdout="$tmp/stdout"
stderr="$tmp/stderr"
write_result "$result" 0 "$base" '["changed.txt"]'

artifacts="$tmp/artifacts"
mkdir -p "$artifacts"
printf '%s\n' '{"state":"pending"}' > "$artifacts/state.json"
printf '%s\n' '{"events":[]}' > "$artifacts/call-log.json"
printf '%s\n' '{"consumed":true}' > "$artifacts/mcp-create.prepared"
cp "$artifacts/state.json" "$tmp/state.before"
cp "$artifacts/call-log.json" "$tmp/call-log.before"
cp "$artifacts/mcp-create.prepared" "$tmp/marker.before"

status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 0 '有効な実装結果を受け入れる'
assert_eq "$(cat "$stdout")" '' '成功時 stdout は空である'
assert_eq "$(cat "$stderr")" '' '成功時 stderr は空である'
cmp "$tmp/state.before" "$artifacts/state.json"
assert_status "$?" 0 'state は検査前後で不変である'
cmp "$tmp/call-log.before" "$artifacts/call-log.json"
assert_status "$?" 0 'call log は検査前後で不変である'
cmp "$tmp/marker.before" "$artifacts/mcp-create.prepared"
assert_status "$?" 0 'prepared marker は検査前後で不変である'

write_result "$result" 1 "$base" '["changed.txt"]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'result の round 不一致を拒否する'
assert_contains "$(cat "$stderr")" 'round' 'round 違反を報告する'
assert_one_line "$stderr" 'round 違反は stderr 一行である'

write_result "$result" 0 'not-the-base' '["changed.txt"]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'result の baseHead 不一致を拒否する'
assert_contains "$(cat "$stderr")" 'baseHead' 'baseHead 違反を報告する'
assert_one_line "$stderr" 'baseHead 違反は stderr 一行である'

repo="$tmp/multiple-commits-repo"
base="$(make_repo "$repo" 'feat: add implementation' 1)"
write_result "$result" 0 "$base" '["changed.txt","second.txt"]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'base から複数 commit の結果を拒否する'
assert_contains "$(cat "$stderr")" 'commit' 'commit 数違反を報告する'
assert_one_line "$stderr" 'commit 数違反は stderr 一行である'

repo="$tmp/changed-files-repo"
base="$(make_repo "$repo" 'feat: add implementation')"
write_result "$result" 0 "$base" '["wrong.txt"]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'changedFiles の集合不一致を拒否する'
assert_contains "$(cat "$stderr")" 'changedFiles' 'changedFiles 違反を報告する'
assert_one_line "$stderr" 'changedFiles 違反は stderr 一行である'

write_result "$result" 0 "$base" '[]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 '空の changedFiles を拒否する'
assert_contains "$(cat "$stderr")" 'changedFiles' '空の changedFiles を報告する'
assert_one_line "$stderr" '空の changedFiles は stderr 一行である'

repo="$tmp/dirty-repo"
base="$(make_repo "$repo" 'feat: add implementation')"
write_result "$result" 0 "$base" '["changed.txt"]'
printf 'uncommitted\n' > "$repo/dirty.txt"
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'dirty worktree を拒否する'
assert_contains "$(cat "$stderr")" 'clean' 'dirty worktree を報告する'
assert_one_line "$stderr" 'dirty worktree は stderr 一行である'

repo="$tmp/non-conventional-repo"
base="$(make_repo "$repo" 'not conventional')"
write_result "$result" 0 "$base" '["changed.txt"]'
status=0
run_check "$repo" "$base" 0 "$result" || status=$?
assert_status "$status" 2 'Conventional Commit でない subject を拒否する'
assert_contains "$(cat "$stderr")" 'Conventional' 'commit subject 違反を報告する'
assert_one_line "$stderr" 'commit subject 違反は stderr 一行である'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
