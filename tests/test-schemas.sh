#!/usr/bin/env bash
# plan-auditor の配布済み JSON Schema 契約を検証する。
set -u

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  printf '  ok: %s\n' "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$1" >&2
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

root="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

auditor="$(chezmoi execute-template --source "$root" \
  '{{ includeTemplate "agent-defs/schemas/plan-auditor.json" . }}' 2>/dev/null || true)"
assert_contains "$auditor" '"findings"' 'plan-auditor schema が出力される'
assert_contains "$auditor" '"decisionRequest"' 'decisionRequest を持つ'
assert_not_contains "$auditor" 'decisionRequestPath' 'read role の path field を持たない'

schema_file="$tmp/plan-auditor.json"
printf '%s' "$auditor" > "$schema_file"

required="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(schema.required.slice().sort().join(","));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$required" 'decisionRequest,findings,summary' 'top-level required が完全一致する'

finding_required="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(schema.properties.findings.items.required.slice().sort().join(","));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$finding_required" 'id,kind,planQuote,problem,question,taskNumbers' \
  'finding の required が 6 欄である'

top_level_closed="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(String(schema.additionalProperties === false));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$top_level_closed" true 'top-level additionalProperties が false である'

finding_closed="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(String(schema.properties.findings.items.additionalProperties === false));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$finding_closed" true 'finding additionalProperties が false である'

kind_enum="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(schema.properties.findings.items.properties.kind.enum.slice().sort().join(","));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$kind_enum" 'constraint-conflict,contradiction,review-standard-violation' \
  'kind enum が 3 値である'

task_numbers_type="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const property = schema.properties.findings.items.properties.taskNumbers;
process.stdout.write(`${property.type}:${property.items.type}`);
' "$schema_file" 2>/dev/null || true)"
assert_eq "$task_numbers_type" 'array:integer' 'taskNumbers が integer array である'

json_schema="$root/private_dot_agents/skills/_shared/scripts/executable_json-schema"
valid_status=0
node - "$schema_file" "$json_schema" <<'NODE' || valid_status=$?
const fs = require('fs')
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const { validateSchema } = require(process.argv[3])
const instance = {
  findings: [{
    id: 'PA-1',
    kind: 'contradiction',
    taskNumbers: [1, 2],
    planQuote: 'Task 1 and Task 2 conflict',
    problem: 'The dependency direction is ambiguous.',
    question: 'Which dependency should be authoritative?'
  }],
  summary: 'One plan contradiction requires a decision.',
  decisionRequest: null
}
const errors = validateSchema(schema, instance, '')
if (errors.length) {
  console.error(errors.join('\n'))
  process.exit(1)
}
NODE
assert_eq "$valid_status" 0 '全 6 欄を持つ finding の valid instance が通る'

invalid_status=0
node - "$schema_file" "$json_schema" <<'NODE' || invalid_status=$?
const fs = require('fs')
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const { validateSchema } = require(process.argv[3])
const instance = {
  findings: [{
    id: 'PA-1',
    kind: 'contradiction',
    taskNumbers: [1],
    planQuote: 'quote',
    problem: 'problem',
    question: 'question',
    unexpected: true
  }],
  summary: 'summary',
  decisionRequestPath: '/tmp/request.json',
  decisionRequest: null
}
if (validateSchema(schema, instance, '').length === 0) process.exit(1)
NODE
assert_eq "$invalid_status" 0 '未知 field を含む instance が拒否される'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
