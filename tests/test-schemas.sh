#!/usr/bin/env bash
# Paseo MAD が配る現行 role の structured output schema を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

for a in implementer task-reviewer re-reviewer final-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"
  if printf '%s' "$out" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>JSON.parse(s))' 2>/dev/null; then
    TESTS_RUN=$((TESTS_RUN + 1)); _pass "$a: JSON として読める"
  else
    TESTS_RUN=$((TESTS_RUN + 1)); _fail "$a: JSON として読める" "パースに失敗した"
  fi
  if [ "$a" != implementer ]; then
    assert_contains "$out" '"round"' "$a: round を持つ"
  fi
done

impl="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/implementer.json" . }}')"
for field in baseHead changedFiles summary decisionRequestPath; do
  assert_contains "$impl" "\"$field\"" "implementer: $field を持つ"
done
req="$(printf '%s' "$impl" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
for field in baseHead changedFiles summary decisionRequestPath; do
  assert_contains "$req" "$field" "implementer: $field は required"
done

rev="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/task-reviewer.json" . }}')"
assert_contains "$rev" '"specVerdict"' "task-reviewer: spec verdict を持つ"
assert_contains "$rev" '"qualityVerdict"' "task-reviewer: quality verdict を持つ"
rev_req="$(printf '%s' "$rev" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
for field in specVerdict qualityVerdict findings round head packageBase packageHead cannotVerify strengths; do
  assert_contains "$rev_req" "$field" "task-reviewer: $field は required"
done

rere="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/re-reviewer.json" . }}')"
assert_contains "$rere" '"verdicts"' "re-reviewer: 指摘ごとの verdict を持つ"
rere_req="$(printf '%s' "$rere" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
for field in verdicts newBreakage outOfScope round head packageBase packageHead; do
  assert_contains "$rere_req" "$field" "re-reviewer: $field は required"
done

fin="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/final-reviewer.json" . }}')"
assert_contains "$fin" '"mustFixBeforeMerge"' "final-reviewer: triage を持つ"
fin_req="$(printf '%s' "$fin" | node -e 'let s="";process.stdin.on("data",c=>s+=c).on("end",()=>console.log(JSON.parse(s).required.join(",")))')"
for field in status readyToMerge findings round head packageBase packageHead triage strengths reasoning; do
  assert_contains "$fin_req" "$field" "final-reviewer: $field は required"
done

for a in implementer task-reviewer re-reviewer final-reviewer; do
  out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$a.json\" . }}")"
  bad="$(printf '%s' "$out" | node -e '
let s="";process.stdin.on("data",c=>s+=c).on("end",()=>{
  const bad=[]; const walk=(o,p="(root)")=>{
    if(Array.isArray(o)) return o.forEach(x=>walk(x,p)); if(!o||typeof o!=="object") return;
    const ts=Array.isArray(o.type)?o.type:[o.type];
    if(ts.includes("object")){const req=new Set(o.required||[]), props=Object.keys(o.properties||{}); const miss=props.filter(k=>!req.has(k)); if(miss.length)bad.push(p+":"+miss.join(",")); if(o.additionalProperties!==false)bad.push(p+":additionalProperties")}
    for(const [k,v] of Object.entries(o))walk(v,(k==="properties"||k==="items")?p+"."+k:p)
  };walk(JSON.parse(s));console.log(bad.join(" / "))
})')"
  assert_eq "$bad" "" "$a: structured output の制約を満たす"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
