#!/usr/bin/env bash
# MAD の設定アセットが揃っていて、互いに整合していることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
for f in manifests paseo-providers paseo-routing paseo-project-routing; do
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/$f.json\" . }}" > "$FIXTURE/$f.json"
done

# JSON として妥当である。
for f in paseo-providers paseo-routing paseo-project-routing; do
  ok="$(jq empty "$FIXTURE/$f.json" 2>/dev/null && echo yes || echo no)"
  assert_eq "$ok" "yes" "$f.json: JSON として妥当"
done

# provider ごとに tier 4 つの model と thinking、read/write の mode が揃っている。
for p in $(jq -r 'keys[]' "$FIXTURE/paseo-providers.json"); do
  for t in fast work think deep; do
    v="$(jq -r --arg p "$p" --arg t "$t" '.[$p].models[$t] // ""' "$FIXTURE/paseo-providers.json")"
    assert_not_contains "|$v|" "||" "$p: models.$t がある"
    v="$(jq -r --arg p "$p" --arg t "$t" '.[$p].thinking[$t] // ""' "$FIXTURE/paseo-providers.json")"
    assert_not_contains "|$v|" "||" "$p: thinking.$t がある"
  done
  for a in read write; do
    v="$(jq -r --arg p "$p" --arg a "$a" '.[$p].modes[$a] // ""' "$FIXTURE/paseo-providers.json")"
    assert_not_contains "|$v|" "||" "$p: modes.$a がある"
  done
  v="$(jq -r --arg p "$p" '.[$p].family // ""' "$FIXTURE/paseo-providers.json")"
  assert_not_contains "|$v|" "||" "$p: family がある"
done

# routing の役割は manifests に存在し、候補の provider は providers に存在する。
for role in $(jq -r 'keys[]' "$FIXTURE/paseo-routing.json"); do
  known="$(jq -r --arg r "$role" 'has($r)' "$FIXTURE/manifests.json")"
  assert_eq "$known" "true" "routing: $role が manifests にある"
  n="$(jq --arg r "$role" '.[$r] | length' "$FIXTURE/paseo-routing.json")"
  assert_not_contains "|$n|" "|0|" "routing: $role に候補がある"
  for p in $(jq -r --arg r "$role" '.[$r][].provider' "$FIXTURE/paseo-routing.json"); do
    known="$(jq -r --arg p "$p" 'has($p)' "$FIXTURE/paseo-providers.json")"
    assert_eq "$known" "true" "routing: $role の候補 $p が providers にある"
  done
done

# 5 つの汎用の役割がすべて routing にある。
for role in researcher synthesizer judge reviewer implementer; do
  known="$(jq -r --arg r "$role" 'has($r)' "$FIXTURE/paseo-routing.json")"
  assert_eq "$known" "true" "routing: $role がある"
done

# 既定の provider は claude と codex の 2 つである。
for p in claude codex; do
  known="$(jq -r --arg p "$p" 'has($p)' "$FIXTURE/paseo-providers.json")"
  assert_eq "$known" "true" "providers: 既定に $p がある"
done
fam="$(jq -r '.claude.family' "$FIXTURE/paseo-providers.json")"
assert_eq "$fam" "claude" "providers: claude の family は claude"
fam="$(jq -r '.codex.family' "$FIXTURE/paseo-providers.json")"
assert_eq "$fam" "codex" "providers: codex の family は codex"

# 規則は配列である。データが無い環境では 0 件になる。
kind="$(jq -r '.rules | type' "$FIXTURE/paseo-project-routing.json")"
assert_eq "$kind" "array" "project-routing: rules は配列"

# 2 つのアセットは chezmoi のテンプレートで、追加分を data から読む。
prov_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/paseo-providers.json")"
assert_contains "$prov_src" 'index . "mad"' "providers: テンプレートが mad のデータを読む"
assert_contains "$prov_src" '"providers"' "providers: テンプレートが mad.providers を読む"
rules_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/paseo-project-routing.json")"
assert_contains "$rules_src" '"projectRules"' "project-routing: テンプレートが mad.projectRules を読む"

# プロジェクト規則は name と match を持ち、providerMap の置換先が providers にある。
n="$(jq '.rules | length' "$FIXTURE/paseo-project-routing.json")"
i=0
while [ "$i" -lt "$n" ]; do
  name="$(jq -r ".rules[$i].name // \"\"" "$FIXTURE/paseo-project-routing.json")"
  assert_not_contains "|$name|" "||" "rule[$i]: name がある"
  m="$(jq -c ".rules[$i].match" "$FIXTURE/paseo-project-routing.json")"
  has="$(printf '%s' "$m" | jq -r 'if (.remote // "") != "" or (.path // "") != "" then "yes" else "no" end')"
  assert_eq "$has" "yes" "rule[$i]: match に remote か path がある"
  for p in $(jq -r ".rules[$i].providerMap // {} | to_entries[].value" "$FIXTURE/paseo-project-routing.json"); do
    known="$(jq -r --arg p "$p" 'has($p)' "$FIXTURE/paseo-providers.json")"
    assert_eq "$known" "true" "rule[$i]: 置換先 $p が providers にある"
  done
  i=$((i + 1))
done

# 配布先に .tmpl がある。
for f in paseo-providers paseo-routing paseo-project-routing; do
  assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_agents/agent-defs/$f.json.tmpl" ] && echo yes || echo no)" \
            "yes" "$f: 配布用の .tmpl がある"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
