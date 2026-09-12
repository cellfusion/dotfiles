#!/usr/bin/env bash
# Paseo MCP だけを backend とする MAD の dispatch/create/state 契約を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SHARE="$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config"
FIXTURES="$CHEZMOI_SOURCE/tests/fixtures/agent-config"
MAD_FIXTURES="$FIXTURES/mad"
MAD_RUNNER="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
MAD_CONTRACT="$SHARE/mad-contract.js"
GENERATOR="$CHEZMOI_SOURCE/private_dot_local/bin/executable_generate-paseo-config"
VALID="$FIXTURES/valid-v1.json"
SUCCESS_ADAPTER="$MAD_FIXTURES/adapter/fake-success-adapter.sh"
NON_GIT_DIR="$(mktemp -d)"
TMP="$(mktemp -d)"
trap 'rm -rf "$NON_GIT_DIR" "$TMP"' EXIT
umask 077

REPRESENTATIVE="$CHEZMOI_SOURCE/tests/manual/mad-representative-run.sh"
FIXTURE_EVIDENCE="$FIXTURES/mad/representative-ok"
env -u MAD_REPRESENTATIVE_RUN_APPROVED DECISION_REQUEST_PATH="$TMP/decision.md" \
  bash "$REPRESENTATIVE" --run --evidence-dir "$TMP/evidence" >/dev/null 2>&1
status=$?
assert_eq "$([ "$status" -ne 0 ] && printf yes || printf no)" "yes" "representative: 承認は外側の前提条件である"
assert_eq "$(test -f "$TMP/decision.md" && echo yes || echo no)" "yes" "representative: 未承認なら decision request を書く"
assert_eq "$(test -e "$TMP/evidence/create-call.json" && echo yes || echo no)" "no" "representative: 未承認なら create を試さない"
assert_not_contains "$(cat "$REPRESENTATIVE" 2>/dev/null)" 'MAD_REPRESENTATIVE_RUN_APPROVED=1' "representative: runner は承認変数へ代入しない"

find "$FIXTURE_EVIDENCE" -type f -exec chmod 600 {} +
bash "$REPRESENTATIVE" --verify-only --evidence-dir "$FIXTURE_EVIDENCE"
assert_eq "$?" "0" "representative: fixture の証跡検査は承認なしで通る"
assert_eq "$(jq -r '.create_calls' "$FIXTURE_EVIDENCE/create-call.json")" "1" "representative: create はちょうど一回"
assert_eq "$(jq -c '.request | keys | sort' "$FIXTURE_EVIDENCE/create-call.json")" \
  '["initialPrompt","notifyOnFinish","provider","settings","title","workspaceId"]' "representative: create payload の key set"
assert_eq "$(jq -c '.request.settings | keys | sort' "$FIXTURE_EVIDENCE/create-call.json")" \
  '["features","modeId","thinkingOptionId"]' "representative: settings の key set"
assert_eq "$(jq -r '.request.settings.modeId' "$FIXTURE_EVIDENCE/create-call.json")" "auto" "representative: modeId は auto"
assert_eq "$(jq -c '.runStates' "$FIXTURE_EVIDENCE/state-transition.json")" '["running","ok"]' "representative: run の遷移"
assert_eq "$(jq -c '.phaseStates' "$FIXTURE_EVIDENCE/state-transition.json")" \
  '["plan:ok","implement:ok","review:ok","fix:ok"]' "representative: 各 phase が完了した"
assert_eq "$(jq -c '[.events[].operation]' "$FIXTURE_EVIDENCE/call-log.json")" \
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request","create_agent"]' \
  "representative: call log の並び"
assert_eq "$(jq '[.events[] | select(.operation == "create_agent") | .callCount] | add' "$FIXTURE_EVIDENCE/call-log.json")" "1" \
  "representative: create_agent はちょうど一回"
for evidence in snapshot.json launch.json create-call.json call-log.json state-transition.json \
  plan/result.json plan/handoff.json implement/result.json implement/handoff.json \
  review/result.json review/handoff.json fix/result.json fix/handoff.json; do
  assert_eq "$(stat -f '%HT:%Lp' "$FIXTURE_EVIDENCE/$evidence")" "Regular File:600" "representative: $evidence は 0600 の regular file"
done
for phase in plan implement review fix; do
  assert_eq "$(jq -r '.artifact_paths | type == "array" and all(.[]; type == "string" and startswith("/"))' \
    "$FIXTURE_EVIDENCE/$phase/handoff.json")" "true" \
    "representative: $phase の handoff は絶対 path だけを持つ"
  assert_eq "$(jq -r '.artifact_paths | all(.[]; startswith("/fixture/"))' \
    "$FIXTURE_EVIDENCE/$phase/handoff.json")" "true" \
    "representative: $phase の fixture artifact は環境非依存 placeholder"
done

if [ "${MAD_REPRESENTATIVE_RUN_APPROVED:-0}" = 1 ]; then
  PHASE_ADAPTER="$TMP/fake-representative-phase-adapter.sh"
  cat > "$PHASE_ADAPTER" <<'EOF'
#!/usr/bin/env bash
set -u

success_adapter="${PASEO_FAKE_SUCCESS_ADAPTER:?}"

write_phase() {
  local phase="$1"
  local result_path="$2"
  local handoff_path="$3"
  printf '{"status":"ok","phase":"%s"}\n' "$phase" > "$result_path.tmp"
  chmod 600 "$result_path.tmp"
  mv "$result_path.tmp" "$result_path"
  jq -cn --arg phase "$phase" --arg artifact "$result_path" \
    '{run_id:"fake-run",node:$phase,attempt:"fake",artifact_paths:[$artifact]}' > "$handoff_path.tmp"
  chmod 600 "$handoff_path.tmp"
  mv "$handoff_path.tmp" "$handoff_path"
}

case "${1:-}" in
  list-providers|list-models)
    exec "$success_adapter" "$@"
    ;;
  create-agent)
    "$success_adapter" "$@" || exit 1
    request_path="${3:-}"
    prompt="$(jq -r '.initialPrompt' "$request_path")"
    for phase in plan implement review fix; do
      result_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase result: //p")"
      handoff_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase handoff: //p")"
      [ -n "$result_path" ] && [ -n "$handoff_path" ] || exit 1
      write_phase "$phase" "$result_path" "$handoff_path"
    done
    state_path="$(printf '%s\n' "$prompt" | sed -n 's/^state transition: //p')"
    [ -n "$state_path" ] || exit 1
    printf '%s\n' '{"runStates":["running","ok"],"phaseStates":["plan:ok","implement:ok","review:ok","fix:ok"]}' > "$state_path.tmp"
    chmod 600 "$state_path.tmp"
    mv "$state_path.tmp" "$state_path"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$PHASE_ADAPTER"

  APPROVED_ROOT="$TMP/approved-root"
  mkdir -p "$APPROVED_ROOT"
  PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_MIGRATION_EVIDENCE_DIR="$APPROVED_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
    bash "$REPRESENTATIVE" --run --evidence-dir "$APPROVED_ROOT/representative" >/dev/null 2>&1
  approved_status=$?
  assert_eq "$approved_status" "0" "representative: fake adapter が実 phase artifact を返す run は成功する"
  assert_eq "$(cat "$APPROVED_ROOT/representative-decision.txt")" "approved-success" \
    "representative: 実 phase 検証後だけ success decision を書く"
  bash "$REPRESENTATIVE" --verify-only --evidence-dir "$APPROVED_ROOT/representative" >/dev/null 2>&1
  assert_eq "$?" "0" "representative: 実 phase artifact の verify-only が通る"
  for phase in plan implement review fix; do
    assert_eq "$(stat -f '%Lp' "$APPROVED_ROOT/representative/$phase/result.json")" "600" \
      "representative: $phase の実 result は 0600"
    assert_eq "$(stat -f '%Lp' "$APPROVED_ROOT/representative/$phase/handoff.json")" "600" \
      "representative: $phase の実 handoff は 0600"
  done

  TIMEOUT_ROOT="$TMP/timeout-root"
  TIMEOUT_REQUEST="$TMP/timeout-request.md"
  mkdir -p "$TIMEOUT_ROOT"
  PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MIGRATION_EVIDENCE_DIR="$TIMEOUT_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=0 DECISION_REQUEST_PATH="$TIMEOUT_REQUEST" \
    bash "$REPRESENTATIVE" --run --evidence-dir "$TIMEOUT_ROOT/representative" >/dev/null 2>&1
  timeout_status=$?
  assert_eq "$([ "$timeout_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: phase timeout は非ゼロで終了する"
  assert_eq "$(test -f "$TIMEOUT_REQUEST" && echo yes || echo no)" "yes" \
    "representative: phase timeout は decision request を書く"
  assert_eq "$(test -e "$TIMEOUT_ROOT/representative/plan/result.json" && echo yes || echo no)" "no" \
    "representative: phase timeout は後続 artifact を生成しない"
  assert_eq "$(test -e "$TIMEOUT_ROOT/representative-decision.txt" && echo yes || echo no)" "no" \
    "representative: phase timeout は success decision を書かない"
fi

out="$(MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=0 bash "$MAD_RUNNER" --select-backend 2>&1)"
assert_eq "$?" "1" "backend: MCP が無ければ Paseo-only run を開始しない"
assert_contains "$out" 'paseo-mcp' "backend: 必要な backend を述べる"
runner_source="$(cat "$MAD_RUNNER")"
for legacy in claude-headless codex-headless --resolve-candidates --check-usage; do
  assert_not_contains "$runner_source" "$legacy" "backend: $legacy の経路を持たない"
done

for role in implementer task-reviewer re-reviewer final-reviewer; do
  assert_eq "$(test -f "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/prompts/$role.md" && echo yes || echo no)" "yes" \
    "role map: $role の prompt がある"
  assert_eq "$(test -f "$CHEZMOI_SOURCE/.chezmoitemplates/agent-defs/schemas/$role.json" && echo yes || echo no)" "yes" \
    "role map: $role の schema がある"
  assert_eq "$(jq -r --arg role "$role" '.agentRoles[$role].artifactContract' "$VALID")" "mad-attempt-v1" \
    "role map: $role は mad-attempt-v1 を返す"
  node "$GENERATOR" --input "$VALID" resolve --project "$NON_GIT_DIR" --role "$role" \
    --provenance mad-dispatch --snapshot "$MAD_FIXTURES/snapshot.json" >/dev/null
  assert_eq "$?" "0" "role map: $role は launch を解決できる"
done
manifest="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" '{{ includeTemplate "agent-defs/manifests.json" . }}')"
routing="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" '{{ includeTemplate "agent-defs/routing.json" . }}')"
paseo_routing="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" '{{ includeTemplate "agent-defs/paseo-routing.json" . }}')"
for role in implementer task-reviewer re-reviewer final-reviewer; do
  assert_eq "$(printf '%s' "$manifest" | jq -r --arg role "$role" 'has($role)')" "true" \
    "role map: manifest に $role がある"
  assert_eq "$(printf '%s' "$routing" | jq -r --arg role "$role" 'has($role)')" "true" \
    "role map: routing に $role がある"
  assert_eq "$(printf '%s' "$paseo_routing" | jq -r --arg role "$role" 'has($role)')" "true" \
    "role map: Paseo routing に $role がある"
done
for legacy_role in sdd-implementer sdd-implementer-think sdd-task-reviewer sdd-re-reviewer sdd-final-reviewer; do
  assert_eq "$(printf '%s' "$manifest" | jq -r --arg role "$legacy_role" 'has($role)')" "false" \
    "role map: manifest に旧 role $legacy_role がない"
  assert_eq "$(printf '%s' "$routing" | jq -r --arg role "$legacy_role" 'has($role)')" "false" \
    "role map: routing に旧 role $legacy_role がない"
  assert_eq "$(printf '%s' "$paseo_routing" | jq -r --arg role "$legacy_role" 'has($role)')" "false" \
    "role map: Paseo routing に旧 role $legacy_role がない"
done
assert_not_contains "$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")" \
  'mcp__paseo__create_agent' "create: manual doc は adapter だけを使う"

export_json="$TMP/resolved-export.json"
enumeration_json="$TMP/provider-enumeration.json"
node -e 'require(process.argv[1]).writeResolvedExport0600(process.argv[2], process.argv[3])' \
  "$MAD_CONTRACT" "$VALID" "$export_json"
assert_eq "$(jq -r '.scope' "$export_json")" "export" "export: scope は export"
assert_eq "$(stat -f '%HT:%Lp' "$export_json")" "Regular File:600" "export: 0600 の regular file"
node -e 'require(process.argv[1]).writeProviderEnumeration0600(process.argv[2], process.argv[3])' \
  "$MAD_CONTRACT" "$export_json" "$enumeration_json"
assert_eq "$(jq -c 'keys|sort' "$enumeration_json")" '["providerIds","type","version"]' "enumerate: key set"
assert_eq "$(jq -r '.type' "$enumeration_json")" "paseo-provider-enumeration" "enumerate: discriminator"
assert_eq "$(jq -c '.providerIds' "$enumeration_json")" \
  '["claude","claude-lab","codex","codex-lab","opencode","pie"]' "enumerate: materialized provider ID 全件列挙"
for forbidden_subcommand in export enumerate-providers; do
  node "$GENERATOR" --input "$VALID" "$forbidden_subcommand" >/dev/null 2>&1
  assert_eq "$?" "2" "CLI: spec の契約表に無い $forbidden_subcommand を受け付けない"
done

attempt="$TMP/mad-success"
mkdir -p "$attempt"
out="$(EXPECTED_PASEO_MAD_SHARE_DIR="$SHARE" bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$SHARE" --input "$VALID" --adapter "$SUCCESS_ADAPTER" \
  --attempt-dir "$attempt" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$attempt/call-log.json")"
assert_eq "$?" "0" "MAD 成功: adapter を通した完全な run が成功する"
assert_eq "$out" "" "MAD 成功: runner は stdout を出さない"
assert_eq "$(jq -c '[.events[].operation]' "$attempt/call-log.json")" \
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request","create_agent"]' \
  "MAD 成功: 呼び出しの順序"
assert_eq "$(jq -c '.events[0].providerIds' "$attempt/call-log.json")" \
  '["claude","claude-lab","codex","codex-lab","opencode","pie"]' "MAD 成功: provider ID を全件列挙する"
assert_eq "$(jq '[.events[] | select(.operation == "list_providers")] | length' "$attempt/call-log.json")" "1" \
  "MAD 成功: list_providers の event は 1 件"
assert_eq "$(jq '[.events[] | select(.operation == "list_providers") | .callCount] | add' "$attempt/call-log.json")" "1" \
  "MAD 成功: list_providers の callCount は 1"
assert_eq "$(jq -c '.events[] | select(.operation == "list_providers") | .materializedProviderIds' "$attempt/call-log.json")" \
  "$(jq -c '.providerIds' "$enumeration_json")" "MAD 成功: 列挙と照合する provider ID が一致する"
available="$(jq -c '.events[] | select(.operation == "list_providers") | .availableProviderIds' "$attempt/call-log.json")"
assert_eq "$available" '["claude","codex"]' "MAD 成功: available な provider は 2 件"
queried="$(jq -c '[.events[] | select(.operation == "list_models") | .provider] | sort' "$attempt/call-log.json")"
assert_eq "$queried" "$(printf '%s' "$available" | jq -c 'sort')" \
  "MAD 成功: available な provider だけに list_models を一回ずつ呼ぶ"
assert_eq "$(jq -c '[.events[] | select(.operation == "list_models") | .callCount] | unique' "$attempt/call-log.json")" \
  '[1]' "MAD 成功: list_models の callCount は provider ごとに 1"
unavailable_queried="$(jq -c --argjson available "$available" \
  '[.events[] | select(.operation == "list_models") | .provider | select(. as $p | $available | index($p) | not)]' \
  "$attempt/call-log.json")"
assert_eq "$unavailable_queried" '[]' "MAD 成功: available でない provider に list_models を呼ばない"
assert_eq "$(stat -f '%HT:%Lp' "$attempt/snapshot.json")" "Regular File:600" "MAD 成功: snapshot は 0600 の regular file"
assert_eq "$(jq -S . "$attempt/snapshot.json")" "$(jq -S . "$MAD_FIXTURES/snapshot.json")" \
  "MAD 成功: 正規化した snapshot は fixture と一致する"
assert_eq "$(jq -r '.events[] | select(.operation == "resolve") | "\(.exitCode) \(.outputType) \(.stdoutDocuments)"' "$attempt/call-log.json")" \
  "0 mad-launch-spec 1" "MAD 成功: resolve は成功し stdout は 1 件"
assert_eq "$(jq -c '.events[] | select(.operation == "build_create_request") | [.topLevelKeys, .settingsKeys, .mode, .regularFile, .validatedBeforeWrite]' "$attempt/call-log.json")" \
  '[["title","workspaceId","initialPrompt","notifyOnFinish","provider","settings"],["modeId","thinkingOptionId","features"],600,true,true]' \
  "MAD 成功: request は検証してから 0600 で書く"
assert_eq "$(stat -f '%HT:%Lp' "$attempt/create-request.json")" "Regular File:600" "MAD 成功: create-request は 0600 の regular file"
assert_eq "$(jq -c '[.events[] | select(.operation == "create_agent") | .payload]' "$attempt/call-log.json")" \
  '[{"title":"fixture title","workspaceId":"fixture-workspace","initialPrompt":"fixture prompt","notifyOnFinish":true,"provider":"codex/sample-work","settings":{"modeId":"auto","thinkingOptionId":"high","features":{}}}]' \
  "MAD 成功: create_agent は完全な payload を受け取る"
assert_eq "$(jq '[.events[] | select(.operation == "create_agent") | .callCount] | add' "$attempt/call-log.json")" "1" \
  "MAD 成功: create_agent は一回だけ"
assert_eq "$(jq -r '.state' "$attempt/state.json")" "running" "MAD 成功: state は running"
assert_not_contains "$(cat "$attempt/call-log.json")" 'https://' "MAD 成功: raw な URL を残さない"

broken_share="$TMP/broken-share"
mkdir -p "$broken_share"
printf '%s\n' "module.exports = require('./missing-module.js')" > "$broken_share/mad-contract.js"
broken_attempt="$TMP/mad-broken-contract"
mkdir -p "$broken_attempt"
out="$(bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$broken_share" --input "$VALID" --adapter "$SUCCESS_ADAPTER" \
  --attempt-dir "$broken_attempt" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$broken_attempt/call-log.json" 2>/dev/null)"
assert_eq "$?" "2" "MAD contract load: 壊れた share-dir を拒否する"
assert_eq "$out" "" "MAD contract load: stdout を出さない"
assert_eq "$(jq -r '.events[-1] | [.operation,.stage,.createCalls,.state] | join(" ")' "$broken_attempt/call-log.json")" \
  "failure resolve 0 failed" "MAD contract load: adapter を呼ばずに failed にする"
assert_eq "$(test -e "$broken_attempt/create-request.json" && echo yes || echo no)" "no" \
  "MAD contract load: request を作らない"

fail_case() {
  stage="$1"; adapter="$2"; role="$3"; input_config="$4"; expected_exit="$5"; expected_state="$6"
  dir="$TMP/mad-fail-$stage"
  mkdir -p "$dir"
  bash "$MAD_RUNNER" --exercise-success \
    --generator "$GENERATOR" --share-dir "$SHARE" --input "$input_config" --adapter "$adapter" \
    --attempt-dir "$dir" --project "$NON_GIT_DIR" --role "$role" \
    --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
    --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$dir/call-log.json" \
    >"$dir/stdout" 2>/dev/null
  status=$?
  assert_eq "$status" "$expected_exit" "MAD 失敗 $stage: exit $expected_exit"
  assert_eq "$(cat "$dir/stdout")" "" "MAD 失敗 $stage: stdout を出さない"
  assert_eq "$(jq -r '.events[-1] | "\(.operation) \(.stage) \(.createCalls) \(.state)"' "$dir/call-log.json")" \
    "failure $stage 0 $expected_state" "MAD 失敗 $stage: 終端 event が no-call を記録する"
  assert_eq "$(test -e "$dir/create-request.json" && echo yes || echo no)" "no" "MAD 失敗 $stage: request を作らない"
  assert_eq "$(jq -r '.state' "$dir/state.json")" "$expected_state" "MAD 失敗 $stage: state は $expected_state"
  assert_not_contains "$(cat "$dir/call-log.json")" 'claude-headless' "MAD 失敗 $stage: native へ落ちない"
}
fail_case discovery "$MAD_FIXTURES/adapter/fake-discovery-failure-adapter.sh" task-reviewer "$VALID" 2 waiting_for_user
fail_case list_models "$MAD_FIXTURES/adapter/fake-list-models-failure-adapter.sh" task-reviewer "$VALID" 2 waiting_for_user
fail_case resolve "$SUCCESS_ADAPTER" task-reviewer "$FIXTURES/exhausted-v1.json" 4 waiting_for_user

create_dir="$TMP/mad-fail-create"
mkdir -p "$create_dir"
bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$SHARE" --input "$VALID" \
  --adapter "$MAD_FIXTURES/adapter/fake-create-rejection-adapter.sh" \
  --attempt-dir "$create_dir" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$create_dir/call-log.json" \
  >/dev/null 2>&1
assert_eq "$?" "1" "MAD 失敗 create_agent: exit 1"
assert_eq "$(jq -r '.events[-1] | "\(.stage) \(.createCalls) \(.state)"' "$create_dir/call-log.json")" \
  "create_agent 1 failed" "MAD 失敗 create_agent: 一回だけ試して failed にする"
assert_eq "$(jq '[.events[] | select(.operation == "create_agent")] | length' "$create_dir/call-log.json")" "1" \
  "MAD 失敗 create_agent: retry しない"

MAD_CONTRACT="$MAD_CONTRACT" LAUNCH_DIR="$FIXTURES/launch" node - <<'NODE'
const contract = require(process.env.MAD_CONTRACT)
const fs = require('node:fs')
const path = require('node:path')
const read = (name) => JSON.parse(fs.readFileSync(path.join(process.env.LAUNCH_DIR, name), 'utf8'))
const context = { title: 't', workspaceId: 'w', initialPrompt: 'p', notifyOnFinish: true }
const request = contract.buildMadCreateRequestV1(read('success.json'), {}, context)
if (Object.keys(request).join(',') !== 'title,workspaceId,initialPrompt,notifyOnFinish,provider,settings') process.exit(1)
if (Object.keys(request.settings).join(',') !== 'modeId,thinkingOptionId,features') process.exit(1)
if (request.provider !== 'codex/sample-work') process.exit(1)
for (const [file, allowlist] of [
  ['exhausted.json', {}],
  ['invalid-extra-field.json', {}],
  ['invalid-non-auto-mode.json', {}],
  ['invalid-unlisted-feature.json', {}],
  ['invalid-non-integer-feature.json', { retries: 'integer' }],
]) {
  let code = null
  try { contract.buildMadCreateRequestV1(read(file), allowlist, context) } catch (error) { code = error.code; if (error.exitCode !== 2) process.exit(1) }
  if (code !== 'invalid_mad_launch_spec') process.exit(1)
}
process.exit(0)
NODE
assert_eq "$?" "0" "contract: allowlist と integer と auto mode を強制する"

# adapter は discovery の mode/model/thinking 値を opaque なまま転送し、異常な行を捨てずに拒否する。
FAKE_PASEO="$TMP/fake-paseo"
FAKE_PASEO_ARGS="$TMP/fake-paseo-args"
cat > "$FAKE_PASEO" <<'EOF'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "provider" ] && [ "${2:-}" = "ls" ]; then
  if [ "${PASEO_FAKE_MISSING_UNAVAILABLE_MODE_IDS:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"unavailable"}]'
  elif [ "${PASEO_FAKE_MISSING_MODE_IDS:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","defaultMode":"auto"}]'
  elif [ "${PASEO_FAKE_BAD_MODE_IDS:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","modeIds":["auto",42]}]'
  elif [ "${PASEO_FAKE_BAD:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","modeIds":["mode: opaque"]},{"provider":"broken","status":"available","modeIds":"not-an-array"}]'
  else
    printf '%s\n' '[{"provider":"codex","status":"available","modeIds":["mode: opaque"]}]'
  fi
  exit 0
fi
if [ "${1:-}" = "provider" ] && [ "${2:-}" = "models" ]; then
  if [ "${PASEO_FAKE_BAD_MODELS:-0}" = "1" ]; then
    printf '%s\n' '[{"id":"model/opaque","thinkingOptionIds":["thinking option"]},{"id":"broken","thinkingOptionIds":"not-an-array"}]'
  else
    printf '%s\n' '[{"id":"model/opaque","thinkingOptionIds":["thinking option"]}]'
  fi
  exit 0
fi
if [ "${1:-}" = "run" ]; then
  printf '%s\n' "$@" > "$PASEO_FAKE_ARGS"
  exit 0
fi
exit 2
EOF
chmod +x "$FAKE_PASEO"
adapter_providers="$(PASEO_CLI="$FAKE_PASEO" "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers)"
assert_eq "$?" "0" "adapter: list-providers は成功する"
assert_eq "$(printf '%s' "$adapter_providers" | jq -c '.providers[0]')" \
  '{"id":"codex","available":true,"modeIds":["mode: opaque"]}' "adapter: modeIds をそのまま転送する"
adapter_models="$(PASEO_CLI="$FAKE_PASEO" "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-models --provider codex)"
assert_eq "$?" "0" "adapter: list-models は成功する"
assert_eq "$(printf '%s' "$adapter_models" | jq -c '.models[0]')" \
  '{"id":"model/opaque","thinkingOptionIds":["thinking option"]}' "adapter: model/thinking option をそのまま転送する"
PASEO_FAKE_MISSING_MODE_IDS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
  >/dev/null 2>&1
assert_eq "$?" "1" "adapter: 欠損 modeIds を defaultMode で補完せず拒否する"
PASEO_FAKE_MISSING_UNAVAILABLE_MODE_IDS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
  >/dev/null 2>&1
assert_eq "$?" "1" "adapter: unavailable の欠損 modeIds を空配列で補完せず拒否する"
PASEO_FAKE_BAD_MODE_IDS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
  >/dev/null 2>&1
assert_eq "$?" "1" "adapter: string array でない modeIds を拒否する"
PASEO_FAKE_BAD=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
  >/dev/null 2>&1
assert_eq "$?" "1" "adapter: 異常な provider 行を破棄せず拒否する"
PASEO_FAKE_BAD_MODELS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-models --provider codex \
  >/dev/null 2>&1
assert_eq "$?" "1" "adapter: 異常な model 行を破棄せず拒否する"
opaque_request="$TMP/opaque-create-request.json"
jq '.notifyOnFinish = false | .provider = "codex/model/opaque" | .settings.thinkingOptionId = "thinking option"' \
  "$MAD_FIXTURES/create-request-success.json" > "$opaque_request"
chmod 600 "$opaque_request"
adapter_create="$(PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_ARGS="$FAKE_PASEO_ARGS" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
  create-agent --request "$opaque_request")"
assert_eq "$?" "0" "adapter: create-agent は検証済み request を受理する"
assert_eq "$adapter_create" '{"status":"accepted"}' "adapter: create-agent の stdout discriminator"
assert_contains "$(cat "$FAKE_PASEO_ARGS")" 'notifyOnFinish=false' "adapter: notifyOnFinish を create payload に渡す"

opaque_attempt="$TMP/mad-opaque-mode"
mkdir -p "$opaque_attempt"
out="$(EXPECTED_PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_OPAQUE_MODE_IDS=1 bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$SHARE" --input "$VALID" --adapter "$SUCCESS_ADAPTER" \
  --attempt-dir "$opaque_attempt" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$opaque_attempt/call-log.json")"
assert_eq "$?" "0" "MAD opaque mode: 実測 modeIds を持つ run が成功する"
assert_eq "$out" "" "MAD opaque mode: runner は stdout を出さない"
assert_eq "$(jq -c '.providers.codex.modeIds' "$opaque_attempt/snapshot.json")" \
  '["auto","mode: observed"]' "MAD opaque mode: 実測 modeIds を snapshot に転送する"
assert_eq "$(jq -c '.providers.claude.modeIds' "$opaque_attempt/snapshot.json")" \
  '["auto","mode: observed"]' "MAD opaque mode: provider ごとの modeIds を保持する"
assert_eq "$(jq -r '.modeId' "$opaque_attempt/launch.json")" "auto" \
  "MAD opaque mode: launch の modeId は auto を維持する"
assert_eq "$(jq -r '[.events[] | select(.operation == "create_agent") | .payload.settings.modeId][0]' "$opaque_attempt/call-log.json")" \
  "auto" "MAD opaque mode: create payload の modeId は auto を維持する"

# 既存の exercise-create 経路も、snapshot または launch の検証前に create を呼ばない。
for invalid_snapshot in malformed invalid-top-level-key providers-models-key-set-mismatch \
  mode-ids-not-string-array model-entry-not-object; do
  create_log="$TMP/exercise-snapshot-$invalid_snapshot.json"
  out="$(bash "$MAD_RUNNER" --exercise-create \
    --share-dir "$SHARE" \
    --snapshot "$FIXTURES/snapshots/$invalid_snapshot.json" \
    --launch "$FIXTURES/launch/success.json" --adapter "$SUCCESS_ADAPTER" \
    --create-log "$create_log" 2>/dev/null)"
  assert_eq "$?" "2" "exercise-create: $invalid_snapshot は exit 2"
  assert_eq "$out" "" "exercise-create: $invalid_snapshot は stdout を出さない"
  assert_eq "$(jq -r '.createCalls' "$create_log")" "0" "exercise-create: $invalid_snapshot は create 0 回"
done
for invalid_launch in exhausted invalid-extra-field invalid-non-auto-mode invalid-unlisted-feature \
  invalid-non-integer-feature; do
  create_log="$TMP/exercise-launch-$invalid_launch.json"
  out="$(bash "$MAD_RUNNER" --exercise-create \
    --share-dir "$SHARE" \
    --snapshot "$FIXTURES/snapshots/all-available.json" \
    --launch "$FIXTURES/launch/$invalid_launch.json" --adapter "$SUCCESS_ADAPTER" \
    --create-log "$create_log" 2>/dev/null)"
  assert_eq "$?" "2" "exercise-create: $invalid_launch は exit 2"
  assert_eq "$out" "" "exercise-create: $invalid_launch は stdout を出さない"
  assert_eq "$(jq -r '.createCalls' "$create_log")" "0" "exercise-create: $invalid_launch は create 0 回"
done

assert_contains "$(cat "$CHEZMOI_SOURCE/tests/test-distribution.sh")" \
  '.local/share/agent-config/mad-contract.js' "distribution: MAD の契約 module を配る"
assert_contains "$(cat "$CHEZMOI_SOURCE/tests/test-distribution.sh")" \
  '.agents/skills/multi-agent-development/scripts/paseo-mcp-adapter' "distribution: adapter を配る"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
