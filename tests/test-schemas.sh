#!/usr/bin/env bash
# 配布済み JSON Schema と implementer prompt の契約を検証する。
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

top_level_types="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const properties = schema.properties;
process.stdout.write(JSON.stringify([properties.findings.type, properties.summary.type, properties.decisionRequest.type]));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$top_level_types" '["array","string",["object","null"]]' \
  'top-level properties の type が正しい'

finding_property_types="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const properties = schema.properties.findings.items.properties;
process.stdout.write([
  properties.id.type,
  properties.kind.type,
  properties.planQuote.type,
  properties.problem.type,
  properties.question.type
].join(","));
' "$schema_file" 2>/dev/null || true)"
assert_eq "$finding_property_types" 'string,string,string,string,string' \
  'finding properties の type が正しい'

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

implementer_prompt="$(chezmoi execute-template --source "$root" \
  '{{ includeTemplate "agent-defs/prompts/implementer.md" . }}' 2>/dev/null || true)"
implementer_schema="$(chezmoi execute-template --source "$root" \
  '{{ includeTemplate "agent-defs/schemas/implementer.json" . }}' 2>/dev/null || true)"
implementer_schema_file="$tmp/implementer.json"
printf '%s' "$implementer_schema" > "$implementer_schema_file"

implementer_required="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(schema.required.slice().sort().join(","));
' "$implementer_schema_file" 2>/dev/null || true)"
assert_eq "$implementer_required" \
  'baseHead,changedFiles,decisionRequestPath,reportPath,round,status,summary' \
  'implementer schema の required が完全集合である'

implementer_closed="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(String(schema.additionalProperties === false));
' "$implementer_schema_file" 2>/dev/null || true)"
assert_eq "$implementer_closed" true 'implementer schema の additionalProperties が false である'

implementer_status_enum="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(schema.properties.status.enum.slice().sort().join(","));
' "$implementer_schema_file" 2>/dev/null || true)"
assert_eq "$implementer_status_enum" 'BLOCKED,DONE,DONE_WITH_CONCERNS,NEEDS_CONTEXT' \
  'implementer status enum が 4 値である'

implementer_property_types="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const properties = schema.properties;
process.stdout.write(JSON.stringify([
  properties.status.type,
  properties.round.type,
  properties.reportPath.type,
  properties.decisionRequestPath.type
]));
' "$implementer_schema_file" 2>/dev/null || true)"
assert_eq "$implementer_property_types" \
  '["string","integer",["string","null"],["string","null"]]' \
  'implementer status/round/reportPath/decisionRequestPath の type が正しい'

implementer_round_minimum="$(node -e '
const schema = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(String(schema.properties.round.minimum));
' "$implementer_schema_file" 2>/dev/null || true)"
assert_eq "$implementer_round_minimum" 0 'implementer round の minimum が 0 である'

implementer_valid_status=0
node - "$implementer_schema_file" "$json_schema" <<'NODE' || implementer_valid_status=$?
const fs = require('fs')
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const { validateSchema } = require(process.argv[3])
const instance = {
  baseHead: '281bf9a6bea53b8e802a2fcb62daef2b1a652f4e',
  changedFiles: ['.chezmoitemplates/agent-defs/prompts/implementer.md'],
  summary: 'Implemented the contract.',
  decisionRequestPath: null,
  status: 'DONE',
  round: 0,
  reportPath: '/private/tmp/report/log.md'
}
const errors = validateSchema(schema, instance, '')
if (errors.length) {
  console.error(errors.join('\n'))
  process.exit(1)
}
NODE
assert_eq "$implementer_valid_status" 0 'implementer の全 required 欄を持つ valid instance が通る'

implementer_invalid_status=0
node - "$implementer_schema_file" "$json_schema" <<'NODE' || implementer_invalid_status=$?
const fs = require('fs')
const schema = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const { validateSchema } = require(process.argv[3])
const instance = {
  baseHead: 'base',
  changedFiles: [],
  summary: 'summary',
  decisionRequestPath: null,
  status: 'UNKNOWN',
  round: -1,
  reportPath: 'relative/log.md'
}
if (validateSchema(schema, instance, '').length === 0) process.exit(1)
NODE
assert_eq "$implementer_invalid_status" 0 '未知 status と負の round を拒否する'

step_four="$(printf '%s\n' "$implementer_prompt" | awk '/^4\. /{f=1} /^5\. /{f=0} f')"
step_four_count="$(printf '%s\n' "$implementer_prompt" | awk '/^4\. /{count++} /^5\. /{f=1} END{print count+0}')"
assert_eq "$step_four_count" 1 '行頭 4. の手順が手順4だけである'
assert_contains "$step_four" 'DONE_WITH_CONCERNS' '完了時の懸念 status を定義する'
assert_contains "$step_four" 'NEEDS_CONTEXT' 'context 不足時の status を定義する'
assert_contains "$step_four" 'DONE' '完了 status を定義する'
assert_contains "$step_four" 'BLOCKED' 'blocked status を定義する'
assert_contains "$step_four" 'Conventional Commit' 'DONE 系だけ Conventional Commit を要求する'
assert_contains "$step_four" 'clean worktree' 'DONE 系だけ clean worktree を要求する'
assert_contains "$step_four" 'commit せず' 'BLOCKED/NEEDS_CONTEXT は commit しない'
assert_contains "$step_four" '変更を残す' 'BLOCKED/NEEDS_CONTEXT は変更を残す'
assert_contains "$step_four" 'DECISION_REQUEST_PATH' 'escalation の request path を使う'
assert_contains "$step_four" 'decisionRequestPath' 'result の decisionRequestPath を指定する'
assert_contains "$step_four" 'changedFiles' 'result の changedFiles 規則を指定する'
assert_contains "$step_four" 'reportPath' 'result の reportPath 規則を指定する'
assert_contains "$step_four" 'log.md' 'reportPath が log.md を指す'
assert_contains "$step_four" 'absolute path' 'reportPath が absolute path である'
assert_contains "$step_four" 'git status --porcelain --untracked-files=all' 'blocked/context の変更一覧を取得する'
assert_contains "$step_four" 'repository-relative' 'blocked/context の変更一覧が repository-relative である'
assert_contains "$step_four" 'RED' 'TDD の RED を要求する'
assert_contains "$step_four" 'GREEN' 'TDD の GREEN を要求する'

safeguards="$(printf '%s\n' "$implementer_prompt" | awk '/^## 守ること$/{f=1} f')"
assert_contains "$safeguards" '`DONE` と `DONE_WITH_CONCERNS`' \
  '守ることの committed diff 規則を DONE 系に限定する'
assert_contains "$safeguards" 'BLOCKED' \
  '守ることの retained worktree 規則が BLOCKED を対象にする'
assert_contains "$safeguards" 'NEEDS_CONTEXT' \
  '守ることの retained worktree 規則が NEEDS_CONTEXT を対象にする'
assert_contains "$safeguards" 'git status --porcelain --untracked-files=all' \
  '守ることの blocked/context 規則が status paths を使う'
assert_not_contains "$safeguards" \
  '- 報告する `changedFiles` は、`git diff --name-only <base>..HEAD` と完全に一致させる' \
  '守ることに無条件の committed diff 規則を残さない'

for condition in \
  '複数の妥当なアプローチ' \
  'アーキテクチャ上の判断' \
  '渡された範囲を超えたコード' \
  '調べても分からない' \
  '自分のアプローチが正しいか確信を持てない' \
  'プランが想定していない形' \
  '既存コードの再構成' \
  'ファイルを読み続けている' \
  '全体像が掴めない'; do
  assert_contains "$step_four" "$condition" "escalation 条件を含む: $condition"
done

for review_item in \
  '全仕様' \
  '落とした要件' \
  '未処理 edge case' \
  '最善の仕事' \
  '明確で正確な名前' \
  '保守性' \
  'YAGNI' \
  '依頼範囲' \
  '既存パターン' \
  '実際の振る舞い' \
  'TDD 遵守' \
  '十分なテスト' \
  'ノイズのない出力'; do
  assert_contains "$step_four" "$review_item" "self-review 観点を含む: $review_item"
done

assert_not_contains "$(printf '%s\n' "$implementer_prompt" | sed '/^4\. /,$d')" \
  'status' '手順4より前に status の規律を置かない'
assert_not_contains "$(printf '%s\n' "$implementer_prompt" | sed -n '/^5\. /,$p')" \
  'DONE_WITH_CONCERNS' '手順4の後に status の規律を置かない'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
