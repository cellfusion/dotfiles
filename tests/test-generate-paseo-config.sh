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
VALIDATOR="$SHARE/config-validator.js"
RESOLVER="$SHARE/resolver.js"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

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

TARGET="$TMP/paseo-config.json"
printf '{"daemon":{"agentProfiles":[]},"agents":{"providers":{}}}' > "$TARGET"
before="$(shasum -a 256 "$TARGET" | cut -d' ' -f1)"
invalids=(malformed unknown-field cross-reference-unknown-environment cross-reference-unknown-provider cross-reference-unknown-role-tier candidate-duplicate-provider environment-candidate-not-eligible tier-missing tier-fast-present feature-allowlist-unknown-key feature-allowlist-object-value feature-allowlist-wrong-scalar feature-allowlist-non-empty secret-feature secret-allowlist-key unknown-family-with-setup reserved-env-agent-env reserved-env-managed reserved-env-case-variant shared-config-env setup-path-collision setup-path-absolute setup-path-parent setup-path-parent-child-overlap setup-directory-pattern-mismatch generated-id-collision generated-physical-path-collision default-environment-unknown remote-rule-scheme remote-rule-auth remote-rule-port remote-rule-query remote-rule-dot-segment remote-rule-dot-git routing-rule-tier-field)
for invalid in "${invalids[@]}"; do
  out="$(node -e 'const fs=require("node:fs"); const {validateConfig}=require(process.argv[1]); try { validateConfig(fs.readFileSync(process.argv[2],"utf8")); process.exit(0) } catch (error) { process.exit(error.exitCode || 1) }' "$VALIDATOR" "$FIXTURES/invalid/$invalid.json" 2>"$TMP/$invalid.stderr")"
  status=$?
  assert_eq "$status" "2" "validator: $invalid は exit 2"
  assert_eq "$out" "" "validator: $invalid は stdout を出さない"
  assert_eq "$(shasum -a 256 "$TARGET" | cut -d' ' -f1)" "$before" "validator: $invalid は target を変えない"
done

export_json="$(node -e 'const fs=require("node:fs"); const {validateConfig}=require(process.argv[1]); const {resolveExport}=require(process.argv[2]); console.log(JSON.stringify(resolveExport(validateConfig(fs.readFileSync(process.argv[3],"utf8")).config)))' "$VALIDATOR" "$RESOLVER" "$VALID")"
assert_eq "$(printf '%s' "$export_json" | jq -r '.scope')" "export" "catalog: scope は export"
assert_eq "$(printf '%s' "$export_json" | jq -r '.defaultEnvironment')" "primary" "catalog: defaultEnvironment は defaults.environment"
assert_eq "$(printf '%s' "$export_json" | jq -r 'has("selection")')" "false" "catalog: export は selection を持たない"
assert_eq "$(printf '%s' "$export_json" | jq -r '.resolutions | length')" "8" "catalog: 2 environment と 4 tier の組"
assert_eq "$(printf '%s' "$export_json" | jq -c '[.resolutions[] | select(.environment == "lab" and .tier == "work") | .candidates[].family]')" '["codex"]' "catalog: environment tier は common tier を継承しない"
assert_eq "$(printf '%s' "$export_json" | jq -r '[.resolutions[] | select(.environment == "lab" and .tier == "work") | .candidates[].model] | .[0]')" "sample-lab-work" "catalog: environment tier の candidate をそのまま使う"
assert_eq "$(printf '%s' "$export_json" | jq -c '[.resolutions[] | select(.environment == "lab" and .tier == "deep") | .warnings[]]')" '["environment tier missing: lab/deep; using common tier"]' "catalog: tier 欠落の warning は一回だけ"
assert_eq "$(printf '%s' "$export_json" | jq -c '[.resolutions[] | select(.environment == "lab" and .tier == "deep") | .candidates[].family]')" '["claude"]' "catalog: eligibility で filter する"
for forbidden in profileName modeId reasonCode providerId paseo-availability-snapshot; do
  assert_not_contains "$export_json" "$forbidden" "catalog: $forbidden を含まない"
done

NON_GIT_DIR="$TMP/non-git"; mkdir -p "$NON_GIT_DIR"
MISSING_PROJECT="$TMP/missing"
PROJECT_FILE="$TMP/project-file"; : > "$PROJECT_FILE"
GIT_ROOT="$TMP/git-root"; git init -q "$GIT_ROOT"
GIT_SUBDIRECTORY="$GIT_ROOT/nested"; mkdir -p "$GIT_SUBDIRECTORY"
dispatch() {
  node -e 'const fs=require("node:fs"); const {validateConfig}=require(process.argv[1]); const {resolveDispatch}=require(process.argv[2]); try { const config=validateConfig(fs.readFileSync(process.argv[3],"utf8")).config; console.log(JSON.stringify(resolveDispatch(config,{project:process.argv[4],role:process.argv[5],provenance:process.argv[6],tier:process.argv[7]||undefined,environment:process.argv[8]||undefined}))) } catch (error) { process.exit(error.exitCode || 1) }' \
    "$VALIDATOR" "$RESOLVER" "${6:-$VALID}" "$1" "$2" "$3" "${4:-}" "${5:-}"
}

out="$(dispatch "$NON_GIT_DIR" re-reviewer mad-fix fast)"
assert_eq "$(printf '%s' "$out" | jq -r '.scope')" "dispatch" "dispatch: scope は dispatch"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.tier')" "light" "dispatch: fast は light に正規化する"
assert_eq "$(printf '%s' "$out" | jq -r '.defaultEnvironment')" "primary" "dispatch: defaultEnvironment を持つ"
assert_eq "$(printf '%s' "$out" | jq '[.resolutions[].warnings[]] | map(select(. == "compatibility: tier alias normalized to light")) | length')" "1" \
  "dispatch: tier alias の互換 warning は一回だけ"
assert_not_contains "$out" "fast" "dispatch: resolved config に fast を含まない"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.tier, (.resolutions[].tier)' | sort -u | tr '\n' ' ')" "light " \
  "dispatch: 正規化後の tier に fast が残らない"

out="$(dispatch "$NON_GIT_DIR" final-reviewer mad-fix)"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.tier')" "deep" "dispatch: role tier を使う"
out="$(dispatch "$NON_GIT_DIR" reviewer mad-fix)"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.tier')" "work" "dispatch: tier 欠落時は work"
assert_eq "$(printf '%s' "$out" | jq '[.resolutions[].warnings[]] | map(select(. == "tier missing for role reviewer; using work")) | length')" \
  "1" "dispatch: tier 欠落の warning は一回だけ"

dispatch "$NON_GIT_DIR" reviewer plain-caller work >/dev/null 2>&1
assert_eq "$?" "2" "dispatch: 通常 caller の tier override は exit 2"
dispatch "$NON_GIT_DIR" reviewer mad-escalation deep >/dev/null 2>&1
assert_eq "$?" "0" "dispatch: mad-escalation の override は受理する"

for rejected in "non-git" "$MISSING_PROJECT" "$PROJECT_FILE" "$GIT_SUBDIRECTORY"; do
  dispatch "$rejected" reviewer mad-fix >/dev/null 2>&1
  assert_eq "$?" "2" "project: $rejected を拒否する"
done
dispatch "$GIT_ROOT" reviewer mad-fix >/dev/null 2>&1
assert_eq "$?" "0" "project: Git の toplevel そのものは受理する"
dispatch "$NON_GIT_DIR" reviewer mad-fix >/dev/null
assert_eq "$?" "0" "project: 既存の絶対 path の non-Git directory を受理する"
dispatch "$NON_GIT_DIR" reviewer mad-fix "" no-such-environment >/dev/null 2>&1
assert_eq "$?" "2" "project: 不正な明示 environment は exit 2"
out="$(dispatch "$NON_GIT_DIR" reviewer mad-fix "" lab)"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "lab" "project: 明示 environment が最優先"

PATH_ROOT="$TMP/path-root"; mkdir -p "$PATH_ROOT/child"
CANONICAL_ROOT="$(cd "$PATH_ROOT" && pwd -P)"
path_config() {
  node -e 'const fs=require("node:fs"); const config=JSON.parse(fs.readFileSync(process.argv[1],"utf8")); const rules=JSON.parse(fs.readFileSync(process.argv[2],"utf8")); config.projectRouting.rules=JSON.parse(JSON.stringify(rules[process.argv[3]]).split("<PROJECT_ROOT>").join(process.argv[4])); fs.writeFileSync(process.argv[5], JSON.stringify(config))' \
    "$VALID" "$FIXTURES/projects/path-rules.json" "$1" "$CANONICAL_ROOT" "$2"
}
path_config exact "$TMP/path-exact.json"
out="$(dispatch "$CANONICAL_ROOT" reviewer mad-fix "" "" "$TMP/path-exact.json")"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "lab" "path: realpath の完全一致で environment を選ぶ"
out="$(dispatch "$CANONICAL_ROOT/child" reviewer mad-fix "" "" "$TMP/path-exact.json")"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "primary" "path: 部分 path は一致しない"
path_config prefix "$TMP/path-prefix.json"
out="$(dispatch "$CANONICAL_ROOT" reviewer mad-fix "" "" "$TMP/path-prefix.json")"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "primary" "path: prefix では一致しない"
path_config glob "$TMP/path-glob.json"
out="$(dispatch "$CANONICAL_ROOT" reviewer mad-fix "" "" "$TMP/path-glob.json")"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "primary" "path: glob では一致しない"
path_config remote-and-path "$TMP/path-and.json"
out="$(dispatch "$CANONICAL_ROOT" reviewer mad-fix "" "" "$TMP/path-and.json")"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "primary" "path: remote と path の両方がある rule は AND で判定する"
assert_eq "$(printf '%s' "$out" | jq '[.resolutions[].warnings[]] | map(select(contains("remote routing skipped"))) | length')" "1" \
  "path: remote を取得できないときは warning だけを足して path の判定を続ける"

REMOTE_GIT_ROOT="$TMP/remote-git-root"; git init -q "$REMOTE_GIT_ROOT"
git -C "$REMOTE_GIT_ROOT" config --add remote.origin.url ""
git -C "$REMOTE_GIT_ROOT" config --add remote.origin.url "https://EXAMPLE.test/Org/Repo.git"
out="$(dispatch "$REMOTE_GIT_ROOT" reviewer mad-fix)"
assert_eq "$(printf '%s' "$out" | jq -r '.selection.environment')" "primary" \
  "remote: 空 URL と有効 URL の混在を unavailable として扱う"
assert_eq "$(printf '%s' "$out" | jq '[.resolutions[].warnings[]] | map(select(contains("remote routing skipped"))) | length')" "1" \
  "remote: 空 URL と有効 URL の混在 warning は一回だけ"

REMOTE_TEST="$RESOLVER" CASES="$FIXTURES/projects/remote-cases.json" node - <<'NODE'
const fs = require('node:fs')
const { canonicalRemoteKey } = require(process.env.REMOTE_TEST)
const cases = JSON.parse(fs.readFileSync(process.env.CASES, 'utf8'))
for (const url of cases.matching) {
  if (canonicalRemoteKey(url) !== 'example.test/Org/Repo') process.exit(1)
}
for (const url of cases.unsupported) {
  if (canonicalRemoteKey(url) !== null) process.exit(1)
}
process.exit(0)
NODE
assert_eq "$?" "0" "remote: SSH と SCP と HTTPS を同じ canonical key へ正規化する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
