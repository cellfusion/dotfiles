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

# MAD の汎用役と delivery が直接起動する author / planner / review 統合役は、Paseo routing にある。
for role in researcher synthesizer judge reviewer implementer spec-author plan-author review-synthesizer; do
  known="$(jq -r --arg r "$role" 'has($r)' "$FIXTURE/paseo-routing.json")"
  assert_eq "$known" "true" "routing: $role がある"
done

# delivery の論理責務は manifest で 1 つの実 role に割り当てる。parent はこの map を
# 読んで、Paseo MCP で同じ role を起動する。
for duty in spec-author spec-reviewer planner plan-reviewer task-graph-analyzer \
            implementer task-reviewer re-reviewer final-reviewer review-synthesizer; do
  owners="$(jq -r --arg duty "$duty" '[to_entries[] | select(.value.delivery_duties | index($duty)) | .key] | length' "$FIXTURE/manifests.json")"
  assert_eq "$owners" "1" "delivery: $duty の実 role が 1 つだけある"
done

# delivery role は backend 非依存の attempt handoff 契約を持ち、prompt / schema / 両 routing
# に実体がある。これにより role 名だけが存在して backend ごとに成果物形式が分かれる事故を防ぐ。
for role in $(jq -r 'to_entries[] | select(.value.delivery_duties | length > 0) | .key' "$FIXTURE/manifests.json"); do
  contract="$(jq -r --arg role "$role" '.[$role].artifact_contract // ""' "$FIXTURE/manifests.json")"
  assert_eq "$contract" "mad-attempt-v1" "delivery: $role は mad-attempt-v1 を使う"
  assert_eq "$([ -f "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/$role.md" ] && echo yes || echo no)" \
            "yes" "delivery: $role の prompt がある"
  assert_eq "$([ -f "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/schemas/$role.json" ] && echo yes || echo no)" \
            "yes" "delivery: $role の schema がある"
  native="$(jq -r --arg role "$role" 'has($role)' "$FIXTURE/paseo-routing.json")"
  assert_eq "$native" "true" "delivery: $role は Paseo MCP で route できる"
done

# refine の改稿役は master から取り込んだ writer である。契約・3 runtime 定義・routing は
# 上の汎用ループが `delivery_duties` を経由してすでに検査している。ここで名指しするのは、
# その `delivery_duties` 自体が壊れるケースだけである。`writer` が配列から抜け落ちると
# writer は汎用ループの対象から静かに外れ、ループは何も言わずに writer を見なくなる。
# `refine` は改稿役を起動できなくなるのに、テストは緑のままになる。
writer_duties="$(jq -r '.writer.delivery_duties | join(",")' "$FIXTURE/manifests.json")"
assert_eq "$writer_duties" "writer" "delivery: writer の論理責務は writer だけ"

# 同じ理由で access が read に変わっても汎用ループは検査しない。writer は書き込み役でなければ
# 対象ファイルを書き換えられず、改稿という職務そのものが果たせなくなる。
writer_access="$(jq -r '.writer.access' "$FIXTURE/manifests.json")"
assert_eq "$writer_access" "write" "delivery: writer は書き込み役"

# 正規成果物を作る役は、status ごとに成功成果物か parent relay 用 decision request のどちらを
# handoff するかを schema で排他的に定める。テンプレートの文字列を探すだけでなく、共有 validator
# に実例を渡して成功と不正な混在の拒否を確認する。
validate_example() {
  local schema="$1"
  local example="$2"
  printf '%s' "$example" | SCHEMA="$schema" \
    VALIDATOR="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_json-schema" node -e '
    const fs = require("fs");
    const { validateSchema } = require(process.env.VALIDATOR);
    let input = "";
    process.stdin.on("data", chunk => { input += chunk; });
    process.stdin.on("end", () => {
      const errors = validateSchema(JSON.parse(fs.readFileSync(process.env.SCHEMA, "utf8")), JSON.parse(input));
      process.stdout.write(errors.length === 0 ? "valid" : "invalid");
    });
  '
}

for role in spec-author plan-author; do
  schema="$FIXTURE/$role-schema.json"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$role.json\" . }}" > "$schema"
  assert_eq "$(validate_example "$schema" '{"status":"ok","artifactPath":"/tmp/canonical.md","decisionRequestPath":null,"summary":"done"}')" \
            "valid" "delivery: $role は成功時に artifactPath だけを受け取る"
  assert_eq "$(validate_example "$schema" '{"status":"needs_decision","artifactPath":null,"decisionRequestPath":"/tmp/decision.md","summary":"need input"}')" \
            "valid" "delivery: $role は判断待ちで decisionRequestPath だけを受け取る"
  assert_eq "$(validate_example "$schema" '{"status":"ok","artifactPath":"/tmp/canonical.md","decisionRequestPath":"/tmp/decision.md","summary":"mixed"}')" \
            "invalid" "delivery: $role は成功時に decision request を混在させない"
  assert_eq "$(validate_example "$schema" '{"status":"needs_decision","artifactPath":"/tmp/canonical.md","decisionRequestPath":null,"summary":"mixed"}')" \
            "invalid" "delivery: $role は判断待ちに成果物を混在させない"
done

# 書ける role は decision request を自分でファイルへ書き、そのパスを返す。
for role in spec-author plan-author implementer writer; do
  schema="$FIXTURE/$role-schema.json"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$role.json\" . }}" > "$schema"
  has="$(jq -r 'if (.properties.decisionRequestPath != null)
                   and ((.required | index("decisionRequestPath")) != null)
                then "yes" else "no" end' "$schema" 2>&1)"
  assert_eq "$has" "yes" "$role: schema が decisionRequestPath を required で持つ"
  access="$(jq -r --arg r "$role" '.[$r].access' \
    "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/manifests.json" 2>&1)"
  assert_eq "$access" "write" "$role: ファイルへ書くので access は write である"
done

# 読み取り専用の role はファイルを書けないので、要求を構造化出力で返す。
# パスを返させると、親が実体の無いパスを run state に記録し、validator が run を落とす。
for role in reviewer researcher judge synthesizer review-synthesizer; do
  schema="$FIXTURE/$role-schema.json"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$role.json\" . }}" > "$schema"
  has="$(jq -r 'if (.properties.decisionRequest != null)
                   and ((.required | index("decisionRequest")) != null)
                then "yes" else "no" end' "$schema" 2>&1)"
  assert_eq "$has" "yes" "$role: schema が decisionRequest を required で持つ"
  assert_eq "$(jq -r 'if .properties.decisionRequestPath == null then "absent" else "present" end' "$schema" 2>&1)" \
            "absent" "$role: 書けないので decisionRequestPath は持たない"
  fields="$(jq -r '.properties.decisionRequest.required | sort | join(",")' "$schema" 2>&1)"
  assert_eq "$fields" "confirmed,options,question,recommendation" \
            "$role: decisionRequest が契約の 4 項目を持つ"
  access="$(jq -r --arg r "$role" '.[$r].access' \
    "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/manifests.json" 2>&1)"
  assert_eq "$access" "read" "$role: 読み取り専用なので access は read である"
done

# 選択肢が 1 つの decision request は、ユーザーに選ばせるものが無い。件数を検証側が
# 見ていないと、schema の minItems が黙って無視される。
dr_schema="$FIXTURE/researcher-schema.json"
chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/researcher.json" . }}' > "$dr_schema"
dr_two='{"summary":"s","findings":["f"],"sources":["src"],"cannotVerify":["c"],"decisionRequest":{"question":"q","options":["a","b"],"recommendation":"r","confirmed":"c"}}'
dr_one='{"summary":"s","findings":["f"],"sources":["src"],"cannotVerify":["c"],"decisionRequest":{"question":"q","options":["a"],"recommendation":null,"confirmed":"c"}}'
dr_old='{"summary":"s","findings":["f"],"sources":["src"],"cannotVerify":["c"],"decisionRequestPath":null}'
assert_eq "$(validate_example "$dr_schema" "$dr_two")" \
  "valid" "decisionRequest: 選択肢が 2 つなら受け入れる"
assert_eq "$(validate_example "$dr_schema" "$dr_one")" \
  "invalid" "decisionRequest: 選択肢が 1 つなら拒否する"
assert_eq "$(validate_example "$dr_schema" "$dr_old")" \
  "invalid" "read 系 role は旧 decisionRequestPath を返せない"

# review 統合は調査統合と異なり、採用 verdict と修正可能な finding を返す専用 role を使う。
review_schema="$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/schemas/review-synthesizer.json"
assert_eq "$(test -f "$review_schema" && echo yes || echo no)" "yes" \
          "delivery: review-synthesizer の schema がある"
if [ -f "$review_schema" ]; then
  rendered_review_schema="$FIXTURE/review-synthesizer-schema.json"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    '{{ includeTemplate "agent-defs/schemas/review-synthesizer.json" . }}' > "$rendered_review_schema"
  assert_contains "$(cat "$rendered_review_schema")" '"verdict"' \
    "delivery: review-synthesizer は verdict を返す"
  assert_contains "$(cat "$rendered_review_schema")" '"severity"' \
    "delivery: review-synthesizer は finding severity を返す"
  assert_contains "$(cat "$rendered_review_schema")" '"location"' \
    "delivery: review-synthesizer は finding location を返す"
  assert_contains "$(cat "$rendered_review_schema")" '"fix"' \
    "delivery: review-synthesizer は finding fix を返す"
  assert_eq "$(validate_example "$rendered_review_schema" '{"verdict":"needs_fixes","findings":[{"severity":"important","summary":"missing test","location":"tests/example.sh:12","fix":"add a regression test","planMandated":true}],"summary":"one actionable issue","strengths":null,"decisionRequest":null}')" \
            "valid" "delivery: review-synthesizer は verdict と修正可能な finding を返す"
fi

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

# provider の一覧は AI 環境の定義から作る。手で書く対応表は持たない。二重に持つと、
# 環境を足したときに Paseo の provider だけが増えて MAD が追従しなくなる。
prov_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/paseo-providers.json")"
assert_contains "$prov_src" 'environments' "providers: テンプレートが environments を読む"
assert_not_contains "$prov_src" 'index . "mad"' "providers: テンプレートは mad.providers を読まない"
rules_src="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/paseo-project-routing.json")"
assert_contains "$rules_src" '"projectRules"' "project-routing: テンプレートが mad.projectRules を読む"

# 環境ごとの provider id は、Paseo の provider を作る 90-agent-envs スクリプトと同じ規則で
# 決まる。先頭環境は接尾辞を持たず、2 つ目以降が `<agent>-<session>` になる。
envs_cfg="$(mktemp)"
cat > "$envs_cfg" <<'EOF'
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "work"
    label   = "P2"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "solo"
    label   = "P3"
    agents  = ["codex"]
EOF
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$envs_cfg" --config-format toml \
  '{{ includeTemplate "agent-defs/paseo-providers.json" . }}' > "$FIXTURE/providers-envs.json"

for p in claude codex claude-work codex-work codex-solo; do
  known="$(jq -r --arg p "$p" 'has($p)' "$FIXTURE/providers-envs.json")"
  assert_eq "$known" "true" "providers: 環境定義から $p を作る"
done
# 環境が持たない AI ツールの provider は作らない。Paseo 側にも存在しないため、
# 候補に残すと解決できない provider を親が選ぶ。
known="$(jq -r 'has("claude-solo")' "$FIXTURE/providers-envs.json")"
assert_eq "$known" "false" "providers: agents に無い claude-solo は作らない"
known="$(jq -r 'has("claude-default")' "$FIXTURE/providers-envs.json")"
assert_eq "$known" "false" "providers: 先頭環境に接尾辞を付けない"

for p in claude claude-work; do
  fam="$(jq -r --arg p "$p" '.[$p].family' "$FIXTURE/providers-envs.json")"
  assert_eq "$fam" "claude" "providers: $p の family は claude"
done
for p in codex codex-work codex-solo; do
  fam="$(jq -r --arg p "$p" '.[$p].family' "$FIXTURE/providers-envs.json")"
  assert_eq "$fam" "codex" "providers: $p の family は codex"
done
# 環境ごとの provider も tier と access の対応を持つ。family の定義をそのまま引くため、
# 既定 provider と同じ model になる。
m="$(jq -r '."claude-work".models.think' "$FIXTURE/providers-envs.json")"
assert_eq "$m" "$(jq -r '.claude.models.think' "$FIXTURE/providers-envs.json")" \
  "providers: claude-work は claude と同じ think model を持つ"

# 環境定義を持たないマシンでは、既定の 2 つだけを作る。clone した直後の状態にあたるので、
# 実行するマシンの private-data.toml ではなく空の設定を与えて確かめる。
empty_cfg="$(mktemp)"
printf '[data]\n' > "$empty_cfg"
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$empty_cfg" --config-format toml \
  '{{ includeTemplate "agent-defs/paseo-providers.json" . }}' > "$FIXTURE/providers-empty.json"
assert_eq "$(jq -c 'keys' "$FIXTURE/providers-empty.json")" '["claude","codex"]' \
  "providers: 環境定義が無ければ claude と codex だけ"
rm -f "$envs_cfg" "$empty_cfg"

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

# 配布する routing も manifest と同じ delivery role 集合を解決できる。
chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/routing.json" . }}' > "$FIXTURE/routing.json"
for role in $(jq -r 'to_entries[] | select(.value.delivery_duties | length > 0) | .key' "$FIXTURE/manifests.json"); do
  known="$(jq -r --arg role "$role" 'has($role)' "$FIXTURE/routing.json")"
  assert_eq "$known" "true" "delivery: $role は配布 routing で route できる"
done

for role in sdd-implementer sdd-implementer-think sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  assert_eq "$(jq -r --arg role "$role" 'has($role)' "$FIXTURE/manifests.json")" "false" \
    "MAD manifest: 旧 role $role がない"
  assert_eq "$(jq -r --arg role "$role" 'has($role)' "$FIXTURE/routing.json")" "false" \
    "MAD routing: 旧 role $role がない"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
