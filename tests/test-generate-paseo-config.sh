#!/usr/bin/env bash
# agent config v1 の共有契約と匿名 fixture を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SHARE="$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config"
FIXTURES="$CHEZMOI_SOURCE/tests/fixtures/agent-config"
SCHEMA="$SHARE/agent-config.schema.json"
SAMPLE="$SHARE/agent-config.sample.json"
TYPES="$SHARE/config-types.js"
VALID="$FIXTURES/valid-v1.json"

assert_eq "$(jq -r '."$schema"' "$SCHEMA")" "https://json-schema.org/draft/2020-12/schema" "schema: Draft 2020-12"
assert_eq "$(jq -c '.tiers | keys' "$SAMPLE")" '["deep","light","think","work"]' "sample: 四 tier をちょうど持つ"
assert_eq "$(jq -r '.defaults.tier' "$SAMPLE")" "work" "sample: defaults.tier は work"
assert_eq "$(jq -c '[.agentRoles[].artifactContract] | unique' "$VALID")" '["mad-attempt-v1"]' "fixture: 全 role の artifactContract は mad-attempt-v1"
assert_eq "$(jq -c '.agentRoles | keys' "$VALID")" '["final-reviewer","implementer","re-reviewer","reviewer","task-reviewer"]' "fixture: delivery role map の 4 役と tier を持たない reviewer"

TYPES="$TYPES" SCHEMA="$SCHEMA" node - <<'NODE'
const fs = require('node:fs')
const { SCHEMA_KEYWORDS } = require(process.env.TYPES)
const schema = JSON.parse(fs.readFileSync(process.env.SCHEMA, 'utf8'))
const seen = new Set()
const walk = (node) => {
  if (Array.isArray(node)) { node.forEach(walk); return }
  if (!node || typeof node !== 'object') return
  for (const [key, value] of Object.entries(node)) {
    seen.add(key)
    if (key === 'properties' || key === 'patternProperties') { Object.values(value).forEach(walk); continue }
    walk(value)
  }
}
walk(schema)
const unsupported = [...seen].filter((key) => !SCHEMA_KEYWORDS.includes(key))
process.exit(unsupported.length === 0 ? 0 : 1)
NODE
assert_eq "$?" "0" "schema: validator が解釈する keyword だけを使う"

for file in "$SAMPLE" "$VALID" "$FIXTURES/resolved/export.json" "$FIXTURES/resolved/dispatch.json"; do
  if jq empty "$file" >/dev/null 2>&1; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "JSON fixture: $(basename "$file") を parse できる"
  else
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "JSON fixture: $(basename "$file") を parse できる"
  fi
done

if jq empty "$FIXTURES/invalid/malformed.json" >/dev/null 2>&1; then
  TESTS_RUN=$((TESTS_RUN + 1)); _fail "invalid fixture: malformed.json は parse に失敗する"
else
  TESTS_RUN=$((TESTS_RUN + 1)); _pass "invalid fixture: malformed.json は parse に失敗する"
fi

for file in "$FIXTURES"/invalid/*.json; do
  [ "$(basename "$file")" = malformed.json ] && continue
  if jq empty "$file" >/dev/null 2>&1; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "invalid fixture: $(basename "$file") は JSON として parse できる"
  else
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "invalid fixture: $(basename "$file") は JSON として parse できる"
  fi
done

TYPES="$TYPES" EXPORT="$FIXTURES/resolved/export.json" DISPATCH="$FIXTURES/resolved/dispatch.json" node - <<'NODE'
const fs = require('node:fs')
const { assertResolvedConfig } = require(process.env.TYPES)
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'))
const exported = assertResolvedConfig(read(process.env.EXPORT))
const dispatched = assertResolvedConfig(read(process.env.DISPATCH))
if (exported.scope !== 'export' || 'selection' in exported) process.exit(1)
if (dispatched.scope !== 'dispatch' || !dispatched.selection) process.exit(1)
const decimalFeature = JSON.parse(JSON.stringify(exported))
decimalFeature.resolutions[0].candidates[0].featureValues.temperature = 0.5
const decimalResolved = assertResolvedConfig(decimalFeature)
if (decimalResolved.resolutions[0].candidates[0].featureValues.temperature !== 0.5) process.exit(1)
for (const resolved of [exported, dispatched]) {
  if (!resolved.environments.some((environment) => environment.name === resolved.defaultEnvironment)) process.exit(1)
}
const withoutDefault = { ...exported }
delete withoutDefault.defaultEnvironment
const invalid = [
  withoutDefault,
  { ...exported, defaultEnvironment: 'not-an-environment' },
  { ...exported, selection: { environment: exported.defaultEnvironment, tier: 'work' } },
  { ...dispatched, selection: { environment: dispatched.defaultEnvironment, tier: 'work', modeId: 'auto' } },
  { ...exported, providerFamilies: [{ ...exported.providerFamilies[0], provider: 'codex' }] },
  { ...exported, resolutions: [{ ...exported.resolutions[0], candidates: [{ provider: 'codex', model: 'm', thinkingOptionId: 'high', featureValues: {} }] }] },
]
for (const value of invalid) {
  let rejected = false
  try { assertResolvedConfig(value) } catch { rejected = true }
  if (!rejected) process.exit(1)
}
process.exit(0)
NODE
assert_eq "$?" "0" "types: defaultEnvironment と scope と Paseo field を検査する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
