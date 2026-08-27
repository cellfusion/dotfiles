#!/usr/bin/env bash
# status スキーマがテンプレートから展開でき、必要な項目を持つことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

for a in sdd-implementer sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"

  # JSON として読める。
  if printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>JSON.parse(s))' 2>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "$a: JSON として読める"
  else
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "$a: JSON として読める" "パースに失敗した"
  fi

  assert_contains "$out" '"round"' "$a: round を持つ"
  if [ "$a" != "sdd-implementer" ]; then
    assert_contains "$out" '"head"' "$a: head を持つ"
  fi
done

impl="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/sdd-implementer.json" . }}')"
assert_contains "$impl" '"DONE_WITH_CONCERNS"' "implementer: status の enum を持つ"
# commit は controller が行う。agent は提案する commit message と、
# 作業開始時の HEAD（controller が dispatch 時の値と照合する）だけを返す。
assert_contains "$impl" '"proposedCommitMessage"' "implementer: commit message を提案する"
assert_contains "$impl" '"baseHead"' "implementer: 作業開始時の HEAD を返す"
assert_contains "$impl" '"changedFiles"' "implementer: 変更したファイルを返す"
# implementer のスキーマは 2 経路で共用する。commit の担い手が経路ごとに違うので、
# 経路ごとの項目を両方 nullable で持つ。片方の都合で property を消さないこと。
#   HERDR_ENV=1  → sdd-run / sdd-task。controller が commit する（baseHead 系を使う）
#   未設定+claude → Workflow。workflow script は shell も git も使えないので
#                   agent 自身が commit する（commits / reviewPackagePath / head を使う）
assert_contains "$impl" '"reviewPackagePath"' "implementer: Workflow 経路の項目を残す"
assert_contains "$impl" '"commits"' "implementer: Workflow 経路の項目を残す"
assert_contains "$impl" '"type": ["string", "null"]' "implementer: 経路ごとの項目は nullable"
req="$(printf '%s' "$impl" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
assert_contains "$req" "baseHead" "implementer: baseHead は required"

# reviewer は引き続き head を持つ（自分が見た package の head と対にする）。
for a in sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"
  assert_contains "$out" '"head"' "$a: head を持つ"
done

impl_prompt="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/sdd-implementer.md")"
assert_contains "$impl_prompt" "git add と git commit は実行しません" \
  "implementer prompt: commit しない"
assert_contains "$impl_prompt" "proposedCommitMessage" \
  "implementer prompt: commit message を提案する"

rev="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/sdd-task-reviewer.json" . }}')"
assert_contains "$rev" '"specVerdict"' "task-reviewer: spec 準拠の verdict を持つ"
assert_contains "$rev" '"qualityVerdict"' "task-reviewer: 品質の verdict を持つ"
assert_contains "$rev" '"cannotVerify"' "task-reviewer: cannotVerify を持つ"

rere="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/sdd-re-reviewer.json" . }}')"
assert_contains "$rere" '"verdicts"' "re-reviewer: 指摘ごとの判定を持つ"
assert_contains "$rere" '"newBreakage"' "re-reviewer: 新しい破壊を持つ"

# レビュアーは自分が見た review package の範囲を必ず返す。呼び出し側が
# 期待した範囲と照合するので、optional では照合が素通りする。
for a in sdd-task-reviewer sdd-re-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"
  req="$(printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
  assert_contains "$req" "packageBase" "$a: packageBase が required"
  assert_contains "$req" "packageHead" "$a: packageHead が required"
done

# 最終レビューの契約。additionalProperties: false なので、消費側（sdd-final-review.js）
# と役割プロンプトが読む項目はすべて properties に無ければならない。
fin="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/sdd-final-reviewer.json" . }}')"
assert_contains "$fin" '"with_fixes"' "final-reviewer: readyToMerge は 3 値"
assert_contains "$fin" '"mustFixBeforeMerge"' "final-reviewer: triage は項目ごとの判定"
assert_contains "$fin" '"strengths": { "type": ["string", "null"] }' "final-reviewer: strengths を持つ"
assert_contains "$fin" '"reasoning": { "type": ["string", "null"] }' "final-reviewer: reasoning を持つ"

# workflow の js はスキーマをテンプレートから取り、自前のリテラルを持たない。
for w in sdd-task sdd-final-review; do
  src="$CHEZMOI_SOURCE/private_dot_config/claude/skills/subagent-driven-development/workflows/$w.js.tmpl"
  assert_contains "$(cat "$src")" 'includeTemplate "agent-defs/schemas' \
    "$w: スキーマをテンプレートから取る"
  assert_not_contains "$(cat "$src")" "enum: ['DONE'," \
    "$w: スキーマのリテラルを持たない"

  # 展開後も JS として構文が通る。
  # このスクリプト本体は workflow ランタイムが async 関数として wrap して実行する
  # 前提のもので、トップレベル return を含む（test-workflows.mjs も同じ理由で
  # AsyncFunction で包んでいる）。素のまま .mjs として構文チェックすると
  # トップレベル return が常に SyntaxError になり、スキーマ展開が壊れていなくても
  # 落ちてしまうため、チェック用にだけ同じ wrap を再現する。
  rendered="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" "$(cat "$src")")"
  printf '%s' "$rendered" > "/tmp/$w-rendered.mjs"
  {
    printf 'async function __check() {\n'
    printf '%s' "$rendered" | sed 's/^export const meta =/const meta =/'
    printf '\n}\n'
  } > "/tmp/$w-rendered.check.mjs"
  if node --check "/tmp/$w-rendered.check.mjs" 2>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "$w: 展開後も JS として通る"
  else
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "$w: 展開後も JS として通る" "node --check に失敗した"
  fi
done

# structured output（codex exec --output-schema）は optional property を許さない。
# 全 property が required に入り、任意の項目は nullable で、すべての object に
# additionalProperties: false が要る。違反すると 400 invalid_json_schema で turn が失敗する。
# 詳細は _cellfusion/specs/2026-08-20-sdd-herdr-remediation.md の §11。
for a in sdd-implementer sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"
  bad="$(printf '%s' "$out" | node -e '
let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{
  const bad=[]
  const walk=(o,p="(root)")=>{
    if (Array.isArray(o)) return o.forEach((x)=>walk(x,p))
    if (!o || typeof o!=="object") return
    const t=o.type, ts=Array.isArray(t)?t:[t]
    if (ts.includes("object")) {
      const req=new Set(o.required||[]), props=Object.keys(o.properties||{})
      const miss=props.filter((k)=>!req.has(k))
      if (miss.length) bad.push(p+": required に無い "+miss.join(","))
      if (o.additionalProperties!==false) bad.push(p+": additionalProperties が false でない")
    }
    for (const [k,v] of Object.entries(o)) walk(v, (k==="properties"||k==="items")?p+"."+k:p)
  }
  walk(JSON.parse(s)); console.log(bad.join(" / "))
})')"
  assert_eq "$bad" "" "$a: structured output の制約を満たす"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
