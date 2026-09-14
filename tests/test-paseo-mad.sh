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
CREATE_BOUNDARY="$MAD_FIXTURES/boundary/fake-mcp-create-boundary.sh"
# 境界 fixture は create 直前に runner の --prepare-create で一回性 marker を取る。
export PASEO_MAD_VALIDATOR="$MAD_RUNNER"
NON_GIT_DIR="$(mktemp -d)"
TMP="$(mktemp -d)"
trap 'rm -rf "$NON_GIT_DIR" "$TMP"' EXIT
umask 077

REPRESENTATIVE="$CHEZMOI_SOURCE/tests/manual/mad-representative-run.sh"
FIXTURE_EVIDENCE="$FIXTURES/mad/representative-ok"

# Unit 3 の clean apply は通常の配布検査から独立した明示承認の経路である。未承認時は
# chezmoi 自体を起動せず、decision request だけを残す。
DISTRIBUTION="$CHEZMOI_SOURCE/tests/test-distribution.sh"
CLEAN_PLAN="$MAD_FIXTURES/plans/valid-plan.md"
CLEAN_BIN="$TMP/clean-bin"
mkdir -p "$CLEAN_BIN"
cat > "$CLEAN_BIN/chezmoi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PASEO_CHEZMOI_LOG"
exit "${PASEO_CHEZMOI_STATUS:-0}"
EOF
chmod 700 "$CLEAN_BIN/chezmoi"

CLEAN_EVIDENCE="$TMP/clean-evidence"
CLEAN_REQUEST="$TMP/clean-decision-request.md"
CLEAN_LOG="$TMP/clean-chezmoi.log"
env -u PASEO_CLEAN_APPLY_APPROVED \
  PATH="$CLEAN_BIN:$PATH" PASEO_CHEZMOI_LOG="$CLEAN_LOG" \
  PASEO_MIGRATION_EVIDENCE_DIR="$CLEAN_EVIDENCE" DECISION_REQUEST_PATH="$CLEAN_REQUEST" \
  bash "$DISTRIBUTION" --clean-apply --plan "$CLEAN_PLAN" >/dev/null 2>&1
clean_status=$?
assert_eq "$([ "$clean_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "clean apply: 未承認なら非ゼロで停止する"
assert_eq "$(test -f "$CLEAN_REQUEST" && echo yes || echo no)" "yes" \
  "clean apply: 未承認なら decision request を書く"
assert_eq "$(test -e "$CLEAN_EVIDENCE/clean-apply-result.txt" && echo yes || echo no)" "no" \
  "clean apply: 未承認なら success evidence を書かない"
assert_eq "$(test -f "$CLEAN_LOG" && cat "$CLEAN_LOG" || true)" "" \
  "clean apply: 未承認なら chezmoi を一度も起動しない"

CLEAN_INVALID_REQUEST="$TMP/clean-invalid-decision-request.md"
CLEAN_INVALID_LOG="$TMP/clean-invalid-chezmoi.log"
env -u PASEO_CLEAN_APPLY_APPROVED \
  PATH="$CLEAN_BIN:$PATH" PASEO_CHEZMOI_LOG="$CLEAN_INVALID_LOG" \
  PASEO_MIGRATION_EVIDENCE_DIR="$TMP/clean-invalid-evidence" DECISION_REQUEST_PATH="$CLEAN_INVALID_REQUEST" \
  bash "$DISTRIBUTION" --clean-apply --plan "$TMP/missing-plan.md" >/dev/null 2>&1
clean_invalid_status=$?
assert_eq "$([ "$clean_invalid_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "clean apply: 未承認なら invalid plan でも非ゼロで停止する"
assert_eq "$(test -f "$CLEAN_INVALID_REQUEST" && echo yes || echo no)" "yes" \
  "clean apply: 未承認なら invalid plan でも decision request を書く"
assert_eq "$(test -f "$CLEAN_INVALID_LOG" && cat "$CLEAN_INVALID_LOG" || true)" "" \
  "clean apply: 未承認なら invalid plan でも chezmoi を起動しない"

# 通常の distribution test は clean apply mode へ入らず、chezmoi apply を呼ばない。
: > "$CLEAN_LOG"
PATH="$CLEAN_BIN:$PATH" PASEO_CHEZMOI_LOG="$CLEAN_LOG" bash "$DISTRIBUTION" >/dev/null 2>&1 || true
assert_eq "$(grep -c '^apply\b' "$CLEAN_LOG" || true)" "0" \
  "distribution: no-arg は chezmoi apply を呼ばない"

# 承認済みの apply は外側から承認変数を渡したときだけ実行する。test 自身は承認しない。
if [ "${PASEO_CLEAN_APPLY_APPROVED:-0}" = 1 ]; then
  CLEAN_FAILED_EVIDENCE="$TMP/clean-failed-evidence"
  CLEAN_FAILED_LOG="$TMP/clean-failed-chezmoi.log"
  mkdir -p "$CLEAN_FAILED_EVIDENCE"
  ( umask 077; printf 'approved-success\n' > "$CLEAN_FAILED_EVIDENCE/clean-apply-result.txt" )
  chmod 600 "$CLEAN_FAILED_EVIDENCE/clean-apply-result.txt"
  PATH="$CLEAN_BIN:$PATH" PASEO_CHEZMOI_LOG="$CLEAN_FAILED_LOG" PASEO_CHEZMOI_STATUS=7 \
    PASEO_MIGRATION_EVIDENCE_DIR="$CLEAN_FAILED_EVIDENCE" \
    bash "$DISTRIBUTION" --clean-apply --plan "$CLEAN_PLAN" >/dev/null 2>&1
  clean_failed_status=$?
  assert_eq "$([ "$clean_failed_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "clean apply: apply が失敗したら非ゼロで停止する"
assert_eq "$(test -e "$CLEAN_FAILED_EVIDENCE/clean-apply-result.txt" && echo yes || echo no)" "no" \
    "clean apply: apply 失敗後に stale success evidence を残さない"

  CLEAN_APPROVED_EVIDENCE="$TMP/clean-approved-evidence"
  PASEO_MIGRATION_EVIDENCE_DIR="$CLEAN_APPROVED_EVIDENCE" \
    bash "$DISTRIBUTION" --clean-apply --plan "$CLEAN_PLAN" >/dev/null 2>&1
  approved_status=$?
  assert_eq "$approved_status" "0" "clean apply: 外側の承認で temporary apply が成功する"
  assert_eq "$(cat "$CLEAN_APPROVED_EVIDENCE/clean-apply-result.txt" 2>/dev/null)" "approved-success" \
    "clean apply: 成功 evidence を書く"
  assert_eq "$(stat -f '%HT:%Lp' "$CLEAN_APPROVED_EVIDENCE/clean-apply-result.txt" 2>/dev/null)" \
    "Regular File:600" "clean apply: success evidence は 0600 regular file"
  CLEAN_STALE_REQUEST="$CLEAN_APPROVED_EVIDENCE/clean-apply-decision-request.md"
  ( umask 077; printf 'pending clean apply\n' > "$CLEAN_STALE_REQUEST"; chmod 600 "$CLEAN_STALE_REQUEST" )
  PASEO_MIGRATION_EVIDENCE_DIR="$CLEAN_APPROVED_EVIDENCE" \
    bash "$DISTRIBUTION" --clean-apply --plan "$CLEAN_PLAN" >/dev/null 2>&1
  assert_eq "$?" "0" "clean apply: stale request があっても approved apply は成功する"
  assert_eq "$(test -e "$CLEAN_STALE_REQUEST" && echo yes || echo no)" "no" \
    "clean apply: approved success は stale request を残さない"
fi

# Unit 3 は八つの前提を個別に集約する。内部 suite は専用 wrapper で成功・失敗を制御し、
# gate 自身の判定と evidence file を実際に検査する。
UNIT_GATE="$CHEZMOI_SOURCE/tests/manual/paseo-unit-gate.sh"
UNIT3_BIN="$TMP/unit3-bin"
mkdir -p "$UNIT3_BIN"
cat > "$UNIT3_BIN/bash" <<'EOF'
#!/bin/bash
case "${1:-}" in
  tests/run-tests.sh|tests/test-paseo-legacy-removal.sh|tests/manual/mad-representative-run.sh) exit "${PASEO_UNIT3_CHECK_STATUS:-0}" ;;
  *) exec /bin/bash "$@" ;;
esac
EOF
chmod 700 "$UNIT3_BIN/bash"
. "$CHEZMOI_SOURCE/tests/lib/unit-gate.sh"

UNIT3_MISSING="$TMP/unit3-missing"
UNIT3_FAILURE_TMP_VICTIM="$TMP/unit3-failure-tmp-victim.txt"
printf 'keep-unit3-failure-tmp-victim\n' > "$UNIT3_FAILURE_TMP_VICTIM"
mkdir -p "$UNIT3_MISSING"
ln -s "$UNIT3_FAILURE_TMP_VICTIM" "$UNIT3_MISSING/unit3-failure.txt.tmp"
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_MISSING" \
  PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_missing_status=$?
assert_eq "$([ "$unit3_missing_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: 前提が無ければ continue を拒否する"
assert_eq "$(cat "$UNIT3_MISSING/unit3-decision.txt" 2>/dev/null)" "rollback" \
  "unit3: 前提不足では rollback を記録する"
assert_contains "$(cat "$UNIT3_MISSING/unit3-failure.txt" 2>/dev/null)" "unit1-decision(exit 1)" \
  "unit3: 失敗した前提と exit code を記録する"
assert_contains "$(cat "$UNIT3_MISSING/unit3-failure.txt" 2>/dev/null)" "Task 8 through Task 11" \
  "unit3: rollback 対象を記録する"
assert_eq "$(stat -f '%HT:%Lp' "$UNIT3_MISSING/unit3-failure.txt" 2>/dev/null)" "Regular File:600" \
  "unit3: failure evidence は 0600 regular file"
assert_eq "$(cat "$UNIT3_FAILURE_TMP_VICTIM")" "keep-unit3-failure-tmp-victim" \
  "unit3: failure evidence の tmp symlink 参照先を変更しない"

UNIT3_OK="$TMP/unit3-ok"
write_unit_decision "$UNIT3_OK/unit1-decision.txt" continue
write_unit_decision "$UNIT3_OK/unit2-decision.txt" continue
write_unit_decision "$UNIT3_OK/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_OK/clean-apply-result.txt" approved-success
printf 'stale failure\n' > "$UNIT3_OK/unit3-failure.txt"
chmod 600 "$UNIT3_OK/unit3-failure.txt"
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_OK" \
  PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_ok_status=$?
assert_eq "$unit3_ok_status" "0" "unit3: 八つの前提が通ると continue を記録する"
assert_eq "$(cat "$UNIT3_OK/unit3-decision.txt" 2>/dev/null)" "continue" \
  "unit3: all-pass は continue decision を書く"
assert_eq "$(stat -f '%HT:%Lp' "$UNIT3_OK/unit3-decision.txt" 2>/dev/null)" "Regular File:600" \
  "unit3: continue decision は 0600 regular file"
assert_eq "$(test -e "$UNIT3_OK/unit3-failure.txt" && echo yes || echo no)" "no" \
  "unit3: all-pass は stale failure evidence を残さない"

UNIT3_NO_PLAN="$TMP/unit3-no-plan"
write_unit_decision "$UNIT3_NO_PLAN/unit1-decision.txt" continue
write_unit_decision "$UNIT3_NO_PLAN/unit2-decision.txt" continue
write_unit_decision "$UNIT3_NO_PLAN/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_NO_PLAN/clean-apply-result.txt" approved-success
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_NO_PLAN" \
  PASEO_PLAN_PATH="$TMP/missing-canonical-plan.md" env -u DECISION_REQUEST_PATH -u PASEO_UNIT3_PLAN_FIXTURE \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_no_plan_status=$?
assert_eq "$([ "$unit3_no_plan_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: 外側 plan が無ければ continue を拒否する"
assert_contains "$(cat "$UNIT3_NO_PLAN/unit3-failure.txt" 2>/dev/null)" "plan-dependency(exit 1)" \
  "unit3: 外側 plan 不在の name と exit code を記録する"

UNIT3_UNFLAGGED_FIXTURE="$TMP/unit3-unflagged-fixture"
write_unit_decision "$UNIT3_UNFLAGGED_FIXTURE/unit1-decision.txt" continue
write_unit_decision "$UNIT3_UNFLAGGED_FIXTURE/unit2-decision.txt" continue
write_unit_decision "$UNIT3_UNFLAGGED_FIXTURE/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_UNFLAGGED_FIXTURE/clean-apply-result.txt" approved-success
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_UNFLAGGED_FIXTURE" \
  PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH -u PASEO_UNIT3_PLAN_FIXTURE \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_unflagged_fixture_status=$?
assert_eq "$([ "$unit3_unflagged_fixture_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: fixture opt-in 無しでは checkout plan を拒否する"
assert_contains "$(cat "$UNIT3_UNFLAGGED_FIXTURE/unit3-failure.txt" 2>/dev/null)" "plan-dependency(exit 2)" \
  "unit3: unflagged fixture の name と exit code を記録する"

UNIT3_BAD_PLAN="$TMP/unit3-bad-plan"
write_unit_decision "$UNIT3_BAD_PLAN/unit1-decision.txt" continue
write_unit_decision "$UNIT3_BAD_PLAN/unit2-decision.txt" continue
write_unit_decision "$UNIT3_BAD_PLAN/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_BAD_PLAN/clean-apply-result.txt" approved-success
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_BAD_PLAN" \
  PASEO_PLAN_PATH='relative-plan.md' PASEO_UNIT3_PLAN_FIXTURE=1 \
  env -u DECISION_REQUEST_PATH /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_bad_plan_status=$?
assert_eq "$([ "$unit3_bad_plan_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: relative plan override では continue を拒否する"
assert_contains "$(cat "$UNIT3_BAD_PLAN/unit3-failure.txt" 2>/dev/null)" "plan-dependency(exit 2)" \
  "unit3: invalid plan の failure name と exit code を記録する"

UNIT3_MIDDLE="$TMP/unit3-middle"
write_unit_decision "$UNIT3_MIDDLE/unit1-decision.txt" continue
write_unit_decision "$UNIT3_MIDDLE/unit2-decision.txt" continue
write_unit_decision "$UNIT3_MIDDLE/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_MIDDLE/clean-apply-result.txt" approved-success
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_MIDDLE" \
  PASEO_UNIT3_CHECK_STATUS=9 PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_middle_status=$?
assert_eq "$([ "$unit3_middle_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: 中間 precondition の失敗で continue を拒否する"
assert_contains "$(cat "$UNIT3_MIDDLE/unit3-failure.txt" 2>/dev/null)" "full-suite(exit 9)" \
  "unit3: 中間 failure の name と exit code を記録する"

UNIT3_REQUEST="$TMP/unit3-request"
write_unit_decision "$UNIT3_REQUEST/unit1-decision.txt" continue
write_unit_decision "$UNIT3_REQUEST/unit2-decision.txt" continue
write_unit_decision "$UNIT3_REQUEST/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_REQUEST/clean-apply-result.txt" approved-success
printf 'pending approval\n' > "$UNIT3_REQUEST/decision-request.md"
chmod 600 "$UNIT3_REQUEST/decision-request.md"
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_REQUEST" \
  DECISION_REQUEST_PATH="$UNIT3_REQUEST/decision-request.md" \
  PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_request_status=$?
assert_eq "$([ "$unit3_request_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: decision request があれば continue を拒否する"
assert_eq "$(cat "$UNIT3_REQUEST/unit3-decision.txt" 2>/dev/null)" "decision_request" \
  "unit3: pending request を decision_request として記録する"
assert_eq "$(stat -f '%HT:%Lp' "$UNIT3_REQUEST/unit3-decision.txt" 2>/dev/null)" "Regular File:600" \
  "unit3: decision request は 0600 regular file"
assert_contains "$(cat "$UNIT3_REQUEST/unit3-failure.txt" 2>/dev/null)" "decision-request(exit 1)" \
  "unit3: decision request も failure evidence に記録する"
assert_eq "$(stat -f '%HT:%Lp' "$UNIT3_REQUEST/unit3-failure.txt" 2>/dev/null)" "Regular File:600" \
  "unit3: decision request failure evidence は 0600 regular file"

UNIT3_DEFAULT_REQUEST="$TMP/unit3-default-request"
write_unit_decision "$UNIT3_DEFAULT_REQUEST/unit1-decision.txt" continue
write_unit_decision "$UNIT3_DEFAULT_REQUEST/unit2-decision.txt" continue
write_unit_decision "$UNIT3_DEFAULT_REQUEST/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_DEFAULT_REQUEST/clean-apply-result.txt" approved-success
printf 'pending default request\n' > "$UNIT3_DEFAULT_REQUEST/clean-apply-decision-request.md"
chmod 600 "$UNIT3_DEFAULT_REQUEST/clean-apply-decision-request.md"
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_DEFAULT_REQUEST" \
  PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_default_request_status=$?
assert_eq "$([ "$unit3_default_request_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: default clean apply request があれば continue を拒否する"
assert_eq "$(cat "$UNIT3_DEFAULT_REQUEST/unit3-decision.txt" 2>/dev/null)" "decision_request" \
  "unit3: default request を decision_request として記録する"

UNIT3_REPRESENTATIVE_REQUEST="$TMP/unit3-representative-request"
write_unit_decision "$UNIT3_REPRESENTATIVE_REQUEST/unit1-decision.txt" continue
write_unit_decision "$UNIT3_REPRESENTATIVE_REQUEST/unit2-decision.txt" continue
write_unit_decision "$UNIT3_REPRESENTATIVE_REQUEST/representative-decision.txt" approved-success
write_unit_decision "$UNIT3_REPRESENTATIVE_REQUEST/clean-apply-result.txt" approved-success
mkdir -p "$UNIT3_REPRESENTATIVE_REQUEST/representative"
printf 'pending representative approval\n' > "$UNIT3_REPRESENTATIVE_REQUEST/representative/representative-decision-request.md"
chmod 600 "$UNIT3_REPRESENTATIVE_REQUEST/representative/representative-decision-request.md"
PATH="$UNIT3_BIN:$PATH" PASEO_MIGRATION_EVIDENCE_DIR="$UNIT3_REPRESENTATIVE_REQUEST" \
  PASEO_UNIT3_PLAN_FIXTURE=1 PASEO_PLAN_PATH="$CLEAN_PLAN" \
  env -u DECISION_REQUEST_PATH \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_representative_request_status=$?
assert_eq "$([ "$unit3_representative_request_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: representative の decision request があれば continue を拒否する"
assert_eq "$(cat "$UNIT3_REPRESENTATIVE_REQUEST/unit3-decision.txt" 2>/dev/null)" "decision_request" \
  "unit3: representative の pending request を decision_request として記録する"
assert_contains "$(cat "$UNIT3_REPRESENTATIVE_REQUEST/unit3-failure.txt" 2>/dev/null)" "representative-decision-request(exit 1)" \
  "unit3: representative request も failure evidence に記録する"

out="$(env -u MAD_REPRESENTATIVE_RUN_APPROVED DECISION_REQUEST_PATH="$TMP/decision.md" \
  bash "$REPRESENTATIVE" --run --evidence-dir "$TMP/evidence" 2>&1)"
status=$?
assert_eq "$status" "2" "representative: live --run は無効化されている"
assert_contains "$out" "disabled" "representative: live --run は無効理由を示す"
assert_eq "$(test -e "$TMP/decision.md" && echo yes || echo no)" "no" "representative: 無効化時に decision request を書かない"
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
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request","create_agent","wait_agent"]' \
  "representative: call log の並び"
assert_eq "$(jq '[.events[] | select(.operation == "create_agent") | .callCount] | add' "$FIXTURE_EVIDENCE/call-log.json")" "1" \
  "representative: create_agent はちょうど一回"
assert_eq "$(jq -c '[.events[] | select(.operation == "wait_agent") | {callCount,timeoutSeconds,status}]' "$FIXTURE_EVIDENCE/call-log.json")" \
  '[{"callCount":1,"timeoutSeconds":1200,"status":"idle"}]' \
  "representative: accepted childRef の wait を一回だけ記録する"
assert_eq "$(jq -c . "$FIXTURE_EVIDENCE/wait-evidence.json")" '{"status":"idle"}' \
  "representative: wait evidence は安全な status だけを持つ"
for evidence in snapshot.json launch.json create-call.json call-log.json state-transition.json wait-evidence.json \
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

if [ "${PASEO_MAD_OFFLINE_FIXTURE_TESTS:-0}" = 1 ]; then
LIVE_PHASE_ADAPTER="$TMP/fake-live-representative-phase-adapter.sh"
cat > "$LIVE_PHASE_ADAPTER" <<'EOF'
#!/usr/bin/env bash
set -u

write_phase() {
  local phase="$1"
  local result_path="$2"
  local handoff_path="$3"
  printf '{"status":"ok","phase":"%s"}\n' "$phase" > "$result_path.tmp"
  chmod 600 "$result_path.tmp"
  mv "$result_path.tmp" "$result_path"
  jq -cn --arg phase "$phase" --arg artifact "$result_path" \
    '{run_id:"live-run",node:$phase,attempt:"live",artifact_paths:[$artifact]}' > "$handoff_path.tmp"
  chmod 600 "$handoff_path.tmp"
  mv "$handoff_path.tmp" "$handoff_path"
}

case "${1:-}" in
  list-providers)
    printf '%s\n' '{"providers":[{"id":"codex","available":true,"modeIds":["auto"]}]}'
    ;;
  list-models)
    [ "${2:-}" = "--provider" ] && [ "${3:-}" = "codex" ] || exit 2
    printf '%s\n' '{"provider":"codex","models":[{"id":"live-model","thinkingOptionIds":["live-thinking"]}]}'
    ;;
  wait-agent)
    [ "${2:-}" = "--child-ref" ] && [ "${3:-}" = "22222222-2222-4222-8222-222222222222" ] && \
      [ "${4:-}" = "--timeout" ] && [ "${5:-}" = "1200" ] || exit 2
    printf '%s\n' '{"status":"idle"}'
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$LIVE_PHASE_ADAPTER"

# 親の mcp__paseo__create_agent に相当する境界。検証済み request を読み、
# 子が書くはずの phase artifact を用意してから accepted response を返す。
LIVE_PHASE_BOUNDARY="$TMP/fake-live-representative-phase-boundary.sh"
cat > "$LIVE_PHASE_BOUNDARY" <<'EOF'
#!/usr/bin/env bash
set -u

write_phase() {
  local phase="$1"
  local result_path="$2"
  local handoff_path="$3"
  printf '{"status":"ok","phase":"%s"}\n' "$phase" > "$result_path.tmp"
  chmod 600 "$result_path.tmp"
  mv "$result_path.tmp" "$result_path"
  jq -cn --arg phase "$phase" --arg artifact "$result_path" \
    '{run_id:"live-run",node:$phase,attempt:"live",artifact_paths:[$artifact]}' > "$handoff_path.tmp"
  chmod 600 "$handoff_path.tmp"
  mv "$handoff_path.tmp" "$handoff_path"
}

request=""
response_out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request) request="${2:-}"; shift 2 ;;
    --response-out) response_out="${2:-}"; shift 2 ;;
    *) exit 2 ;;
  esac
done
[ -n "$request" ] && [ -n "$response_out" ] || exit 2
jq -e '
  .provider == "codex/live-model" and
  .workspaceId == "live-workspace" and
  .settings.thinkingOptionId == "live-thinking"
' "$request" >/dev/null || exit 2

# create の前に一回性 marker を取る。取れなければ create を呼ばない。
attempt_dir="$(cd "$(dirname "$request")" && pwd -P)" || exit 2
bash "${PASEO_MAD_VALIDATOR:?}" --prepare-create --share-dir "${PASEO_MAD_SHARE_DIR:?}" \
  --attempt-dir "$attempt_dir" >/dev/null 2>&1 || exit 2

prompt="$(jq -r '.initialPrompt' "$request")"
for phase in plan implement review fix; do
  result_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase result: //p")"
  handoff_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase handoff: //p")"
  [ -n "$result_path" ] && [ -n "$handoff_path" ] || exit 2
  write_phase "$phase" "$result_path" "$handoff_path"
done
state_path="$(printf '%s\n' "$prompt" | sed -n 's/^state transition: //p')"
[ -n "$state_path" ] || exit 2
printf '%s\n' '{"runStates":["running","ok"],"phaseStates":["plan:ok","implement:ok","review:ok","fix:ok"]}' > "$state_path.tmp"
chmod 600 "$state_path.tmp"
mv "$state_path.tmp" "$state_path"
printf '%s' '{"status":"accepted","childRef":"22222222-2222-4222-8222-222222222222"}' > "$response_out.tmp"
chmod 600 "$response_out.tmp"
mv "$response_out.tmp" "$response_out"
EOF
chmod +x "$LIVE_PHASE_BOUNDARY"

LIVE_ROOT="$TMP/live-root"
mkdir -p "$LIVE_ROOT"
PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$LIVE_PHASE_ADAPTER" \
  PASEO_MAD_CREATE_BOUNDARY="$LIVE_PHASE_BOUNDARY" \
  PASEO_MAD_REPRESENTATIVE_PROVIDER=codex \
  PASEO_MAD_REPRESENTATIVE_MODEL=live-model \
  PASEO_MAD_REPRESENTATIVE_THINKING_OPTION=live-thinking \
  PASEO_MAD_REPRESENTATIVE_WORKSPACE_ID=live-workspace \
  PASEO_MIGRATION_EVIDENCE_DIR="$LIVE_ROOT" \
  MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
  bash "$REPRESENTATIVE" --run --evidence-dir "$LIVE_ROOT/representative" >/dev/null 2>&1
live_status=$?
assert_eq "$live_status" "0" "representative: live override は Codex の実在 candidate と workspace を create へ渡す"
assert_eq "$(jq -r '.request.provider' "$LIVE_ROOT/representative/create-call.json")" "codex/live-model" \
  "representative: live override は provider/model を保持する"
assert_eq "$(jq -r '.request.workspaceId' "$LIVE_ROOT/representative/create-call.json")" "live-workspace" \
  "representative: live override は workspace ID を保持する"
assert_eq "$(jq -r '.request.settings.thinkingOptionId' "$LIVE_ROOT/representative/create-call.json")" "live-thinking" \
  "representative: live override は thinking option を保持する"

INVALID_OVERRIDE_ROOT="$TMP/invalid-override-root"
INVALID_OVERRIDE_REQUEST="$TMP/invalid-override-request.md"
mkdir -p "$INVALID_OVERRIDE_ROOT"
PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$SUCCESS_ADAPTER" \
  PASEO_MAD_CREATE_BOUNDARY="$CREATE_BOUNDARY" \
  PASEO_MAD_REPRESENTATIVE_MODEL=live-model \
  PASEO_MIGRATION_EVIDENCE_DIR="$INVALID_OVERRIDE_ROOT" \
  MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=0 DECISION_REQUEST_PATH="$INVALID_OVERRIDE_REQUEST" \
  bash "$REPRESENTATIVE" --run --evidence-dir "$INVALID_OVERRIDE_ROOT/representative" >/dev/null 2>&1
invalid_override_status=$?
assert_eq "$([ "$invalid_override_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "representative: 不完全な live override は非ゼロで停止する"
assert_eq "$(test -f "$INVALID_OVERRIDE_REQUEST" && echo yes || echo no)" "yes" \
  "representative: 不完全な live override は decision request を書く"
assert_eq "$(test -e "$INVALID_OVERRIDE_ROOT/representative/create-call.json" && echo yes || echo no)" "no" \
  "representative: 不完全な live override は create を試さない"

EMPTY_OVERRIDE_ROOT="$TMP/empty-override-root"
EMPTY_OVERRIDE_REQUEST="$TMP/empty-override-request.md"
mkdir -p "$EMPTY_OVERRIDE_ROOT"
PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$SUCCESS_ADAPTER" \
  PASEO_MAD_CREATE_BOUNDARY="$CREATE_BOUNDARY" \
  PASEO_MAD_REPRESENTATIVE_PROVIDER='' \
  PASEO_MAD_REPRESENTATIVE_MODEL='' \
  PASEO_MAD_REPRESENTATIVE_THINKING_OPTION='' \
  PASEO_MAD_REPRESENTATIVE_WORKSPACE_ID='' \
  PASEO_MIGRATION_EVIDENCE_DIR="$EMPTY_OVERRIDE_ROOT" \
  MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=0 DECISION_REQUEST_PATH="$EMPTY_OVERRIDE_REQUEST" \
  bash "$REPRESENTATIVE" --run --evidence-dir "$EMPTY_OVERRIDE_ROOT/representative" >/dev/null 2>&1
empty_override_status=$?
assert_eq "$([ "$empty_override_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "representative: 空の live override は非ゼロで停止する"
assert_eq "$(test -e "$EMPTY_OVERRIDE_ROOT/representative/create-call.json" && echo yes || echo no)" "no" \
  "representative: 空の live override は create を試さない"

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
  wait-agent)
    exec "$success_adapter" "$@"
    ;;
  *)
    exit 2
    ;;
esac
EOF
  chmod +x "$PHASE_ADAPTER"

  # 親が公式 MCP create を呼ぶ境界。phase artifact は create 後に子が書くものを模す。
  PHASE_BOUNDARY="$TMP/fake-representative-phase-boundary.sh"
  cat > "$PHASE_BOUNDARY" <<'EOF'
#!/usr/bin/env bash
set -u

boundary="${PASEO_FAKE_CREATE_BOUNDARY:?}"

request=""
response_out=""
args=()
while [ "$#" -gt 0 ]; do
  args+=("$1")
  case "$1" in
    --request) request="${2:-}" ;;
    --response-out) response_out="${2:-}" ;;
  esac
  shift
done
[ -n "$request" ] && [ -n "$response_out" ] || exit 2
"$boundary" "${args[@]}" || exit 1

prompt="$(jq -r '.initialPrompt' "$request")"
for phase in plan implement review fix; do
  result_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase result: //p")"
  handoff_path="$(printf '%s\n' "$prompt" | sed -n "s/^$phase handoff: //p")"
  [ -n "$result_path" ] && [ -n "$handoff_path" ] || exit 1
  printf '{"status":"ok","phase":"%s"}\n' "$phase" > "$result_path.tmp"
  chmod 600 "$result_path.tmp"
  mv "$result_path.tmp" "$result_path"
  jq -cn --arg phase "$phase" --arg artifact "$result_path" \
    '{run_id:"fake-run",node:$phase,attempt:"fake",artifact_paths:[$artifact]}' > "$handoff_path.tmp"
  chmod 600 "$handoff_path.tmp"
  mv "$handoff_path.tmp" "$handoff_path"
done
state_path="$(printf '%s\n' "$prompt" | sed -n 's/^state transition: //p')"
[ -n "$state_path" ] || exit 1
printf '%s\n' '{"runStates":["running","ok"],"phaseStates":["plan:ok","implement:ok","review:ok","fix:ok"]}' > "$state_path.tmp"
chmod 600 "$state_path.tmp"
mv "$state_path.tmp" "$state_path"
EOF
  chmod +x "$PHASE_BOUNDARY"

  APPROVED_ROOT="$TMP/approved-root"
  mkdir -p "$APPROVED_ROOT"
  PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_FAKE_CREATE_BOUNDARY="$CREATE_BOUNDARY" PASEO_MAD_CREATE_BOUNDARY="$PHASE_BOUNDARY" \
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
  printf 'stale child artifact\n' > "$APPROVED_ROOT/representative/plan/plan.md"
  chmod 600 "$APPROVED_ROOT/representative/plan/plan.md"
  PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_FAKE_CREATE_BOUNDARY="$CREATE_BOUNDARY" PASEO_MAD_CREATE_BOUNDARY="$PHASE_BOUNDARY" \
    PASEO_MIGRATION_EVIDENCE_DIR="$APPROVED_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
    bash "$REPRESENTATIVE" --run --evidence-dir "$APPROVED_ROOT/representative" >/dev/null 2>&1
  stale_rerun_status=$?
  assert_eq "$stale_rerun_status" "0" "representative: approved rerun は managed stale evidence を無効化する"
  assert_eq "$(test -e "$APPROVED_ROOT/representative/plan/plan.md" && echo yes || echo no)" "no" \
    "representative: approved rerun は stale child evidence を残さない"

  # create の transport は親だけが持つ。境界を渡さない run は成功扱いにしない。
  MISSING_BOUNDARY_ROOT="$TMP/missing-boundary-root"
  MISSING_BOUNDARY_REQUEST="$TMP/missing-boundary-request.md"
  mkdir -p "$MISSING_BOUNDARY_ROOT"
  env -u PASEO_MAD_CREATE_BOUNDARY \
    PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_MIGRATION_EVIDENCE_DIR="$MISSING_BOUNDARY_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 DECISION_REQUEST_PATH="$MISSING_BOUNDARY_REQUEST" \
    bash "$REPRESENTATIVE" --run --evidence-dir "$MISSING_BOUNDARY_ROOT/representative" >/dev/null 2>&1
  missing_boundary_status=$?
  assert_eq "$([ "$missing_boundary_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: create 境界が無い run は非ゼロで停止する"
  assert_eq "$(test -f "$MISSING_BOUNDARY_REQUEST" && echo yes || echo no)" "yes" \
    "representative: create 境界が無い run は decision request を書く"
  assert_eq "$(test -e "$MISSING_BOUNDARY_ROOT/representative/create-call.json" && echo yes || echo no)" "no" \
    "representative: create 境界が無い run は create 証跡を残さない"

  WAIT_FAILURE_ROOT="$TMP/wait-failure-root"
  mkdir -p "$WAIT_FAILURE_ROOT"
  write_unit_decision "$WAIT_FAILURE_ROOT/representative-decision.txt" approved-success
  PASEO_FAKE_WAIT_STATUS=timeout PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_FAKE_CREATE_BOUNDARY="$CREATE_BOUNDARY" PASEO_MAD_CREATE_BOUNDARY="$PHASE_BOUNDARY" \
    PASEO_MIGRATION_EVIDENCE_DIR="$WAIT_FAILURE_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
    bash "$REPRESENTATIVE" --run --evidence-dir "$WAIT_FAILURE_ROOT/representative" >/dev/null 2>&1
  wait_failure_status=$?
  assert_eq "$([ "$wait_failure_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: timeout wait は非ゼロで停止する"
  assert_eq "$(test -e "$WAIT_FAILURE_ROOT/representative-decision.txt" && echo yes || echo no)" "no" \
    "representative: timeout wait 後に stale success decision を残さない"
  assert_eq "$(test -f "$WAIT_FAILURE_ROOT/representative/representative-decision-request.md" && echo yes || echo no)" "yes" \
    "representative: timeout wait は default decision request を残す"

  UNSAFE_STALE_ROOT="$TMP/unsafe-stale-root"
  UNSAFE_STALE_VICTIM="$TMP/unsafe-stale-victim.txt"
  mkdir -p "$UNSAFE_STALE_ROOT/representative"
  printf 'retain unsafe target\n' > "$UNSAFE_STALE_VICTIM"
  ln -s "$UNSAFE_STALE_VICTIM" "$UNSAFE_STALE_ROOT/representative/snapshot.json"
  write_unit_decision "$UNSAFE_STALE_ROOT/representative-decision.txt" approved-success
  PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_FAKE_CREATE_BOUNDARY="$CREATE_BOUNDARY" PASEO_MAD_CREATE_BOUNDARY="$PHASE_BOUNDARY" \
    PASEO_MIGRATION_EVIDENCE_DIR="$UNSAFE_STALE_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
    bash "$REPRESENTATIVE" --run --evidence-dir "$UNSAFE_STALE_ROOT/representative" >/dev/null 2>&1
  unsafe_stale_status=$?
  assert_eq "$([ "$unsafe_stale_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: symlink の stale evidence を拒否する"
  assert_eq "$(cat "$UNSAFE_STALE_VICTIM")" "retain unsafe target" \
    "representative: symlink の参照先を変更しない"
  assert_eq "$(test -f "$UNSAFE_STALE_ROOT/representative/representative-decision-request.md" && echo yes || echo no)" "yes" \
    "representative: unsafe evidence では pending decision request を残す"
  bash "$REPRESENTATIVE" --verify-only --evidence-dir "$UNSAFE_STALE_ROOT/representative" >/dev/null 2>&1
  assert_eq "$([ "$?" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: symlink stale evidence は verify-only でも拒否する"

  UNKNOWN_STALE_ROOT="$TMP/unknown-stale-root"
  mkdir -p "$UNKNOWN_STALE_ROOT/representative"
  printf 'unknown stale evidence\n' > "$UNKNOWN_STALE_ROOT/representative/unexpected.json"
  chmod 600 "$UNKNOWN_STALE_ROOT/representative/unexpected.json"
  write_unit_decision "$UNKNOWN_STALE_ROOT/representative-decision.txt" approved-success
  PASEO_FAKE_SUCCESS_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$PHASE_ADAPTER" \
    PASEO_FAKE_CREATE_BOUNDARY="$CREATE_BOUNDARY" PASEO_MAD_CREATE_BOUNDARY="$PHASE_BOUNDARY" \
    PASEO_MIGRATION_EVIDENCE_DIR="$UNKNOWN_STALE_ROOT" \
    MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS=3 \
    bash "$REPRESENTATIVE" --run --evidence-dir "$UNKNOWN_STALE_ROOT/representative" >/dev/null 2>&1
  unknown_stale_status=$?
  assert_eq "$([ "$unknown_stale_status" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: unknown stale evidence を拒否する"
  assert_eq "$(test -f "$UNKNOWN_STALE_ROOT/representative/representative-decision-request.md" && echo yes || echo no)" "yes" \
    "representative: unknown stale evidence でも pending request を残す"
  bash "$REPRESENTATIVE" --verify-only --evidence-dir "$UNKNOWN_STALE_ROOT/representative" >/dev/null 2>&1
  assert_eq "$([ "$?" -ne 0 ] && printf yes || printf no)" "yes" \
    "representative: unknown stale evidence は verify-only でも拒否する"

  TIMEOUT_ROOT="$TMP/timeout-root"
  TIMEOUT_REQUEST="$TMP/timeout-request.md"
  mkdir -p "$TIMEOUT_ROOT"
  PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$SUCCESS_ADAPTER" \
    PASEO_MAD_CREATE_BOUNDARY="$CREATE_BOUNDARY" \
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
manual_doc="$(cat "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md")"
assert_contains "$manual_doc" \
  'mcp__paseo__create_agent' "create: manual doc は公式 MCP tool を create の経路にする"
assert_contains "$manual_doc" 'mcp-create.json' \
  "create: manual doc は runner が書く request file を名指しする"
assert_not_contains "$manual_doc" 'create-agent --request' \
  "create: manual doc は adapter の create subcommand を残さない"
assert_contains "$manual_doc" 'assertMadCreateRequestV1' \
  "create: manual doc は create 前の request 再検証を求める"
assert_contains "$manual_doc" 'manual-orchestration-validate --assert-create-request' \
  "create: manual doc は create 直前の assertion コマンドを示す"
assert_contains "$manual_doc" 'manual-orchestration-validate --prepare-create' \
  "create: manual doc は create 前の prepare コマンドを示す"
assert_contains "$manual_doc" 'mcp-create.prepared' \
  "create: manual doc は一回だけ create を許す prepare marker を名指しする"
assert_contains "$manual_doc" 'O_EXCL' "create: manual doc は marker の排他生成を示す"
assert_contains "$manual_doc" '--prepare-create` が成功した呼び出しだけが `mcp__paseo__create_agent` を呼べる' \
  "create: manual doc は prepare を create の前提にする"
assert_contains "$manual_doc" '--exercise-accepted` は marker を作らない' \
  "create: manual doc は accepted 境界が marker を作らないと明記する"
for call_log_key in \
  '`create_agent` | `callCount`、`requestPath`、`transport`' \
  '`failure` | `stage`、`exitCode`、`createCalls`、`state`'; do
  assert_contains "$manual_doc" "$call_log_key" "call log: manual doc が $call_log_key を宣言する"
done
assert_contains "$manual_doc" 'create_agent.transport` は `mcp__paseo__create_agent` の一語に固定' \
  "call log: manual doc が transport の固定値を宣言する"
assert_contains "$manual_doc" 'stop-agent --child-ref <safe-id>' \
  "stop: manual doc は adapter stop だけを使う"
assert_contains "$manual_doc" 'stoppedCount' \
  "stop: manual doc は Paseo stop response shape を明記する"
assert_not_contains "$manual_doc" '親が停止するときは同じ ID に `paseo stop' \
  "stop: manual doc は親の raw stop 直書きを残さない"

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
  '["claude","claude-lab","codex","codex-lab","opencode","pi"]' "enumerate: materialized provider ID 全件列挙"
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
assert_eq "$?" "0" "MAD 成功: discovery から request build までが成功する"
assert_eq "$out" "" "MAD 成功: runner は stdout を出さない"
assert_eq "$(jq -c '[.events[].operation]' "$attempt/call-log.json")" \
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request"]' \
  "MAD 成功: 呼び出しの順序"
assert_eq "$(jq -c '.events[0].providerIds' "$attempt/call-log.json")" \
  '["claude","claude-lab","codex","codex-lab","opencode","pi"]' "MAD 成功: provider ID を全件列挙する"
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
assert_eq "$(jq -r '.events[] | select(.operation == "build_create_request") | .path' "$attempt/call-log.json")" \
  "$attempt/mcp-create.json" "MAD 成功: build event は mcp-create.json を指す"
assert_eq "$(stat -f '%HT:%Lp' "$attempt/mcp-create.json")" "Regular File:600" \
  "MAD 成功: mcp-create.json は 0600 の regular file"
assert_eq "$(test -e "$attempt/create-request.json" && echo yes || echo no)" "no" \
  "MAD 成功: 旧 create-request.json を残さない"

# runner は create の transport を実行しない。attempt state は child を持たない。
assert_eq "$(jq -c '[.events[] | select(.operation == "create_agent")]' "$attempt/call-log.json")" '[]' \
  "MAD 成功: runner は create を呼ばない"
assert_eq "$(jq -c . "$attempt/state.json")" '{"state":"pending","create_accepted":false}' \
  "MAD 成功: create 前の attempt state は pending かつ未受理"
assert_eq "$(test -e "$attempt/wait-evidence.json" && echo yes || echo no)" "no" \
  "MAD 成功: create 前に wait を呼ばない"

# fast_mode は正本から launch spec を経て create request の settings.features へ届く。
assert_eq "$(jq -c '.featureValues' "$attempt/launch.json")" '{"fast_mode":true}' \
  "MAD 成功: launch spec が Codex の fast_mode true を持つ"
assert_eq "$(jq -c '.settings.features' "$attempt/mcp-create.json")" '{"fast_mode":true}' \
  "MAD 成功: mcp-create.json の settings.features に fast_mode true を写す"
assert_eq "$(jq -c 'keys' "$attempt/mcp-create.json")" \
  '["initialPrompt","notifyOnFinish","provider","settings","title","workspaceId"]' \
  "MAD 成功: mcp-create.json は公式 MCP create の 6 引数だけを持つ"
assert_eq "$(jq -r '.provider, .settings.modeId, .settings.thinkingOptionId' "$attempt/mcp-create.json" | tr '\n' ' ')" \
  "codex/sample-work auto high " "MAD 成功: provider/model と modeId と thinking option を写す"
assert_not_contains "$(cat "$attempt/call-log.json")" 'fixture prompt' "MAD 成功: prompt を runtime log に残さない"
assert_not_contains "$(cat "$attempt/call-log.json")" 'https://' "MAD 成功: raw な URL を残さない"

# 親が公式 mcp__paseo__create_agent を呼ぶ境界。fake は受け取った payload を観測する。
observed="$TMP/mcp-observed.json"
accepted_response="$TMP/mcp-accepted.json"
PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_MCP_OBSERVED="$observed" bash "$CREATE_BOUNDARY" \
  --request "$attempt/mcp-create.json" --response-out "$accepted_response"
assert_eq "$?" "0" "MCP 境界: 0600 の検証済み request を受理する"
assert_eq "$(jq -c '.settings.features' "$observed")" '{"fast_mode":true}' \
  "MCP 境界: create payload の settings.features に fast_mode true が届く"
assert_eq "$(jq -r '.provider' "$observed")" "codex/sample-work" "MCP 境界: provider/model が届く"
assert_eq "$(jq -r '.settings.modeId' "$observed")" "auto" "MCP 境界: modeId は auto"
assert_eq "$(jq -r '.notifyOnFinish' "$observed")" "true" "MCP 境界: notifyOnFinish が届く"
assert_eq "$(jq -c 'keys | sort' "$observed")" \
  '["initialPrompt","notifyOnFinish","provider","settings","title","workspaceId"]' \
  "MCP 境界: mcp-create.json の 6 key をそのまま渡す"
assert_eq "$(stat -f '%HT:%Lp' "$attempt/mcp-create.prepared")" "Regular File:600" \
  "MCP 境界: create の前に prepare marker を 0600 の regular file として残す"
assert_eq "$(jq -c . "$attempt/mcp-create.prepared")" \
  '{"version":1,"type":"mad-create-prepare","consumed":true}' \
  "MCP 境界: prepare marker は mad-create-prepare の schema を持つ"

out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" --attempt-dir "$attempt" \
  --call-log "$attempt/call-log.json" --adapter "$SUCCESS_ADAPTER" --response "$accepted_response" \
  --wait-timeout 1200)"
assert_eq "$?" "0" "MAD accepted: accepted response を受けた後の境界が成功する"
assert_eq "$out" "" "MAD accepted: runner は stdout を出さない"
assert_eq "$(jq -c '[.events[].operation]' "$attempt/call-log.json")" \
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request","create_agent","wait_agent"]' \
  "MAD accepted: create と wait を call log の末尾に足す"
assert_eq "$(jq -c '[.events[] | select(.operation == "create_agent") | has("payload")]' "$attempt/call-log.json")" \
  '[false]' "MAD accepted: create_agent の runtime log は payload を持たない"
assert_eq "$(jq '[.events[] | select(.operation == "create_agent") | .callCount] | add' "$attempt/call-log.json")" "1" \
  "MAD accepted: create_agent は一回だけ"
assert_eq "$(jq -r '.events[] | select(.operation == "create_agent") | .transport' "$attempt/call-log.json")" \
  "mcp__paseo__create_agent" "MAD accepted: create の transport を公式 MCP tool として記録する"
assert_eq "$(jq -r '.state' "$attempt/state.json")" "running" "MAD accepted: state は running"
assert_eq "$(jq -r '.child_ref' "$attempt/state.json")" "11111111-1111-4111-8111-111111111111" \
  "MAD accepted: create の childRef を attempt state に保存する"
assert_eq "$(jq -r '.create_accepted' "$attempt/state.json")" "true" \
  "MAD accepted: accepted create を attempt state に保存する"
assert_eq "$(jq -c . "$attempt/wait-evidence.json")" '{"status":"idle"}' \
  "MAD accepted: accepted create の後に sanitized wait を記録する"

# fast_mode:false も同じ経路を通す。true だけを通して false を落とす実装を弾く。
FALSE_INPUT="$TMP/valid-fast-mode-false.json"
jq -c '.tiers.work.candidates = [{provider:"claude",model:"sample-think",thinkingOptionId:"high",featureValues:{fast_mode:false}}]' \
  "$VALID" > "$FALSE_INPUT"
false_attempt="$TMP/mad-fast-mode-false"
mkdir -p "$false_attempt"
out="$(EXPECTED_PASEO_MAD_SHARE_DIR="$SHARE" bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$SHARE" --input "$FALSE_INPUT" --adapter "$SUCCESS_ADAPTER" \
  --attempt-dir "$false_attempt" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --call-log "$false_attempt/call-log.json")"
assert_eq "$?" "0" "fast_mode false: Claude の候補で request build まで成功する"
assert_eq "$out" "" "fast_mode false: runner は stdout を出さない"
assert_eq "$(jq -c '.provider, .featureValues' "$false_attempt/launch.json" | tr '\n' ' ')" \
  '"claude" {"fast_mode":false} ' "fast_mode false: launch spec が false を持つ"
assert_eq "$(jq -c '.settings.features' "$false_attempt/mcp-create.json")" '{"fast_mode":false}' \
  "fast_mode false: mcp-create.json の settings.features が false を持つ"
assert_eq "$(stat -f '%HT:%Lp' "$false_attempt/mcp-create.json")" "Regular File:600" \
  "fast_mode false: mcp-create.json は 0600 の regular file"

false_observed="$TMP/mcp-observed-false.json"
false_response="$TMP/mcp-accepted-false.json"
PASEO_MAD_VALIDATOR="$MAD_RUNNER" PASEO_MAD_SHARE_DIR="$SHARE" \
  PASEO_FAKE_MCP_OBSERVED="$false_observed" bash "$CREATE_BOUNDARY" \
  --request "$false_attempt/mcp-create.json" --response-out "$false_response"
assert_eq "$?" "0" "fast_mode false: MCP 境界が検証済み request を受理する"
assert_eq "$(jq -c '.settings.features' "$false_observed")" '{"fast_mode":false}' \
  "fast_mode false: 公式 MCP payload の settings.features に false が届く"
assert_eq "$(jq -r '.settings.features.fast_mode | type' "$false_observed")" "boolean" \
  "fast_mode false: 観測した値は boolean のままである"
assert_eq "$(jq -r '.provider' "$false_observed")" "claude/sample-think" \
  "fast_mode false: Claude の provider/model が届く"

out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" --attempt-dir "$false_attempt" \
  --call-log "$false_attempt/call-log.json" --adapter "$SUCCESS_ADAPTER" --response "$false_response" \
  --wait-timeout 1200)"
assert_eq "$?" "0" "fast_mode false: accepted 境界が成功する"
assert_eq "$out" "" "fast_mode false: runner は stdout を出さない"
assert_eq "$(jq -r '.state, .create_accepted, .child_ref' "$false_attempt/state.json" | tr '\n' ' ')" \
  "running true 11111111-1111-4111-8111-111111111111 " "fast_mode false: state を running へ進める"
assert_eq "$(jq -c '.settings.features' "$false_attempt/mcp-create.json")" '{"fast_mode":false}' \
  "fast_mode false: 受理後も request の false を書き換えない"
assert_eq "$(jq -c '[.events[].operation]' "$false_attempt/call-log.json")" \
  '["enumerate_materialized_provider_ids","list_providers","list_models","list_models","write_snapshot","resolve","build_create_request","create_agent","wait_agent"]' \
  "fast_mode false: call log の並びは true の経路と同じである"

# --exercise-accepted は create を一回だけ受理する。二回目は state と log を変えない。
double_attempt="$TMP/mad-double-accept"
cp -R "$attempt" "$double_attempt"
double_state_before="$(cat "$double_attempt/state.json")"
double_log_before="$(cat "$double_attempt/call-log.json")"
out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" --attempt-dir "$double_attempt" \
  --call-log "$double_attempt/call-log.json" --adapter "$SUCCESS_ADAPTER" --response "$accepted_response" \
  --wait-timeout 1200 2>/dev/null)"
assert_eq "$?" "2" "MAD 二重受理: 二回目は exit 2"
assert_eq "$out" "" "MAD 二重受理: stdout を出さない"
assert_eq "$(cat "$double_attempt/state.json")" "$double_state_before" \
  "MAD 二重受理: attempt state を変更しない"
assert_eq "$(cat "$double_attempt/call-log.json")" "$double_log_before" \
  "MAD 二重受理: call log を変更しない"
assert_eq "$(stat -f '%HT:%Lp' "$attempt/mcp-create.prepared")" "Regular File:600" \
  "MAD 受理: prepare marker は受理後も 0600 の regular file"

# create 前の attempt を再現する。state は pending、call log は create 前の event だけ、
# prepare marker と wait evidence は無い状態にする。
make_pre_create_attempt() {
  local source_attempt="$1"
  local destination="$2"
  rm -rf "$destination"
  cp -R "$source_attempt" "$destination" || return 1
  rm -f "$destination/wait-evidence.json" "$destination/mcp-create.prepared"
  printf '%s' '{"state":"pending","create_accepted":false}' > "$destination/state.json" || return 1
  chmod 600 "$destination/state.json" || return 1
  jq -c '[.events[] | select(.operation != "create_agent" and .operation != "wait_agent")] | {version:1,type:"mad-call-log",events:.}' \
    "$source_attempt/call-log.json" > "$destination/call-log.json" || return 1
  chmod 600 "$destination/call-log.json"
}

# prepare が成功した後の marker を書く。
write_prepare_marker() {
  printf '%s' '{"version":1,"type":"mad-create-prepare","consumed":true}' > "$1" || return 1
  chmod 600 "$1"
}

# --prepare-create は create の直前に一回性 marker を取る。marker を取れた一者だけが
# 公式 mcp__paseo__create_agent を呼べる。
prepare_attempt="$TMP/mad-prepare-create"
make_pre_create_attempt "$attempt" "$prepare_attempt"
prepare_state_before="$(cat "$prepare_attempt/state.json")"
prepare_log_before="$(cat "$prepare_attempt/call-log.json")"
out="$(bash "$MAD_RUNNER" --prepare-create --share-dir "$SHARE" --attempt-dir "$prepare_attempt" 2>/dev/null)"
assert_eq "$?" "0" "prepare: 検証済み request で marker を取れる"
assert_eq "$out" "" "prepare: stdout を出さない"
assert_eq "$(stat -f '%HT:%Lp' "$prepare_attempt/mcp-create.prepared")" "Regular File:600" \
  "prepare: marker は 0600 の regular file"
assert_eq "$(jq -c . "$prepare_attempt/mcp-create.prepared")" \
  '{"version":1,"type":"mad-create-prepare","consumed":true}' "prepare: marker の schema を固定する"
assert_eq "$(cat "$prepare_attempt/state.json")" "$prepare_state_before" "prepare: state を変更しない"
assert_eq "$(cat "$prepare_attempt/call-log.json")" "$prepare_log_before" "prepare: call log を変更しない"

# 二回目の prepare は marker 競合で止まる。marker も state も log も書き換えない。
prepare_marker_before="$(cat "$prepare_attempt/mcp-create.prepared")"
out="$(bash "$MAD_RUNNER" --prepare-create --share-dir "$SHARE" --attempt-dir "$prepare_attempt" 2>/dev/null)"
assert_eq "$?" "2" "prepare 二回目: exit 2"
assert_eq "$out" "" "prepare 二回目: stdout を出さない"
assert_eq "$(cat "$prepare_attempt/mcp-create.prepared")" "$prepare_marker_before" \
  "prepare 二回目: marker を書き換えない"
assert_eq "$(cat "$prepare_attempt/state.json")" "$prepare_state_before" "prepare 二回目: state を変更しない"
assert_eq "$(cat "$prepare_attempt/call-log.json")" "$prepare_log_before" "prepare 二回目: call log を変更しない"

# 2 親が同時に prepare を通ると create を 2 回呼べる。marker は同時実行でも一者だけに渡る。
race_attempt="$TMP/mad-prepare-race"
make_pre_create_attempt "$attempt" "$race_attempt"
race_state_before="$(cat "$race_attempt/state.json")"
race_log_before="$(cat "$race_attempt/call-log.json")"
race_status_dir="$TMP/mad-prepare-race-status"
rm -rf "$race_status_dir"
mkdir -p "$race_status_dir"
for race_index in 1 2 3 4 5 6 7 8; do
  (
    bash "$MAD_RUNNER" --prepare-create --share-dir "$SHARE" --attempt-dir "$race_attempt" >/dev/null 2>&1
    printf '%s' "$?" > "$race_status_dir/$race_index"
  ) &
done
wait
race_winners=0
race_losers=0
for race_index in 1 2 3 4 5 6 7 8; do
  case "$(cat "$race_status_dir/$race_index")" in
    0) race_winners=$((race_winners + 1)) ;;
    2) race_losers=$((race_losers + 1)) ;;
  esac
done
assert_eq "$race_winners" "1" "prepare race: marker を取れる呼び出しは一つだけである"
assert_eq "$race_losers" "7" "prepare race: 敗者はすべて exit 2 で止まる"
assert_eq "$(jq -c . "$race_attempt/mcp-create.prepared")" \
  '{"version":1,"type":"mad-create-prepare","consumed":true}' "prepare race: marker は一件だけ残る"
assert_eq "$(cat "$race_attempt/state.json")" "$race_state_before" "prepare race: state を変更しない"
assert_eq "$(cat "$race_attempt/call-log.json")" "$race_log_before" "prepare race: call log を変更しない"

# request が契約を満たさないとき、prepare は marker を残さない。
for prepare_case in EXTRA_KEY NON_AUTO_MODE UNLISTED_FEATURE WORLD_READABLE; do
  prepare_invalid_attempt="$TMP/mad-prepare-invalid-$prepare_case"
  make_pre_create_attempt "$attempt" "$prepare_invalid_attempt"
  case "$prepare_case" in
    EXTRA_KEY) jq -c '. + {version:1}' "$attempt/mcp-create.json" > "$prepare_invalid_attempt/mcp-create.json" ;;
    NON_AUTO_MODE) jq -c '.settings.modeId = "manual"' "$attempt/mcp-create.json" > "$prepare_invalid_attempt/mcp-create.json" ;;
    UNLISTED_FEATURE) jq -c '.settings.features.verbose = true' "$attempt/mcp-create.json" > "$prepare_invalid_attempt/mcp-create.json" ;;
    WORLD_READABLE) cp "$attempt/mcp-create.json" "$prepare_invalid_attempt/mcp-create.json" ;;
  esac
  if [ "$prepare_case" = WORLD_READABLE ]; then
    chmod 644 "$prepare_invalid_attempt/mcp-create.json"
  else
    chmod 600 "$prepare_invalid_attempt/mcp-create.json"
  fi
  prepare_invalid_state_before="$(cat "$prepare_invalid_attempt/state.json")"
  prepare_invalid_log_before="$(cat "$prepare_invalid_attempt/call-log.json")"
  out="$(bash "$MAD_RUNNER" --prepare-create --share-dir "$SHARE" \
    --attempt-dir "$prepare_invalid_attempt" 2>/dev/null)"
  assert_eq "$?" "2" "prepare 不正 request: $prepare_case は exit 2"
  assert_eq "$out" "" "prepare 不正 request: $prepare_case は stdout を出さない"
  assert_eq "$(test -e "$prepare_invalid_attempt/mcp-create.prepared" && echo yes || echo no)" "no" \
    "prepare 不正 request: $prepare_case は marker を作らない"
  assert_eq "$(cat "$prepare_invalid_attempt/state.json")" "$prepare_invalid_state_before" \
    "prepare 不正 request: $prepare_case は state を変更しない"
  assert_eq "$(cat "$prepare_invalid_attempt/call-log.json")" "$prepare_invalid_log_before" \
    "prepare 不正 request: $prepare_case は call log を変更しない"
done

# state が pending でない、または call log に create 以後の event がある attempt は
# prepare を通さない。marker を作らずに止める。
for prepare_reentry_case in RUNNING_STATE EXTRA_STATE_KEY WORLD_READABLE_STATE \
  CREATE_EVENT_PRESENT NON_CONTIGUOUS_SEQ UNKNOWN_LOG_KEY; do
  prepare_reentry_attempt="$TMP/mad-prepare-reentry-$prepare_reentry_case"
  make_pre_create_attempt "$attempt" "$prepare_reentry_attempt"
  case "$prepare_reentry_case" in
    RUNNING_STATE)
      printf '%s' '{"state":"running","child_ref":"11111111-1111-4111-8111-111111111111","create_accepted":true}' \
        > "$prepare_reentry_attempt/state.json"; chmod 600 "$prepare_reentry_attempt/state.json" ;;
    EXTRA_STATE_KEY)
      printf '%s' '{"state":"pending","create_accepted":false,"note":"extra"}' > "$prepare_reentry_attempt/state.json"
      chmod 600 "$prepare_reentry_attempt/state.json" ;;
    WORLD_READABLE_STATE) chmod 644 "$prepare_reentry_attempt/state.json" ;;
    CREATE_EVENT_PRESENT)
      jq -c '.events += [{seq:(.events | length),operation:"create_agent",callCount:1,requestPath:"/fixture/mcp-create.json",transport:"mcp__paseo__create_agent"}]' \
        "$prepare_reentry_attempt/call-log.json" > "$prepare_reentry_attempt/call-log.tmp"
      mv "$prepare_reentry_attempt/call-log.tmp" "$prepare_reentry_attempt/call-log.json"
      chmod 600 "$prepare_reentry_attempt/call-log.json" ;;
    NON_CONTIGUOUS_SEQ)
      jq -c '.events[-1].seq += 3' "$prepare_reentry_attempt/call-log.json" > "$prepare_reentry_attempt/call-log.tmp"
      mv "$prepare_reentry_attempt/call-log.tmp" "$prepare_reentry_attempt/call-log.json"
      chmod 600 "$prepare_reentry_attempt/call-log.json" ;;
    UNKNOWN_LOG_KEY)
      jq -c '.events[-1].unknown = true' "$prepare_reentry_attempt/call-log.json" > "$prepare_reentry_attempt/call-log.tmp"
      mv "$prepare_reentry_attempt/call-log.tmp" "$prepare_reentry_attempt/call-log.json"
      chmod 600 "$prepare_reentry_attempt/call-log.json" ;;
  esac
  prepare_reentry_state_before="$(cat "$prepare_reentry_attempt/state.json")"
  prepare_reentry_log_before="$(cat "$prepare_reentry_attempt/call-log.json")"
  out="$(bash "$MAD_RUNNER" --prepare-create --share-dir "$SHARE" \
    --attempt-dir "$prepare_reentry_attempt" 2>/dev/null)"
  assert_eq "$?" "2" "prepare 受理前検査: $prepare_reentry_case は exit 2"
  assert_eq "$out" "" "prepare 受理前検査: $prepare_reentry_case は stdout を出さない"
  assert_eq "$(test -e "$prepare_reentry_attempt/mcp-create.prepared" && echo yes || echo no)" "no" \
    "prepare 受理前検査: $prepare_reentry_case は marker を作らない"
  assert_eq "$(cat "$prepare_reentry_attempt/state.json")" "$prepare_reentry_state_before" \
    "prepare 受理前検査: $prepare_reentry_case は state を変更しない"
  assert_eq "$(cat "$prepare_reentry_attempt/call-log.json")" "$prepare_reentry_log_before" \
    "prepare 受理前検査: $prepare_reentry_case は call log を変更しない"
done

# --exercise-accepted は prepare marker を確認するだけで、marker を作らない。
# marker が無い、mode が違う、schema が違う attempt は state と log を変えずに拒否する。
for reentry_case in MISSING_MARKER WORLD_READABLE_MARKER INVALID_MARKER_SCHEMA \
  RUNNING_STATE EXTRA_STATE_KEY WORLD_READABLE_STATE \
  CREATE_EVENT_PRESENT NON_CONTIGUOUS_SEQ UNKNOWN_LOG_KEY; do
  reentry_attempt="$TMP/mad-reentry-$reentry_case"
  make_pre_create_attempt "$attempt" "$reentry_attempt"
  write_prepare_marker "$reentry_attempt/mcp-create.prepared"
  case "$reentry_case" in
    MISSING_MARKER) rm -f "$reentry_attempt/mcp-create.prepared" ;;
    WORLD_READABLE_MARKER) chmod 644 "$reentry_attempt/mcp-create.prepared" ;;
    INVALID_MARKER_SCHEMA)
      printf '%s' '{"version":1,"type":"mad-create-prepare","consumed":true,"note":"extra"}' \
        > "$reentry_attempt/mcp-create.prepared"
      chmod 600 "$reentry_attempt/mcp-create.prepared" ;;
    RUNNING_STATE)
      printf '%s' '{"state":"running","child_ref":"11111111-1111-4111-8111-111111111111","create_accepted":true}' \
        > "$reentry_attempt/state.json"; chmod 600 "$reentry_attempt/state.json" ;;
    EXTRA_STATE_KEY)
      printf '%s' '{"state":"pending","create_accepted":false,"note":"extra"}' > "$reentry_attempt/state.json"
      chmod 600 "$reentry_attempt/state.json" ;;
    WORLD_READABLE_STATE) chmod 644 "$reentry_attempt/state.json" ;;
    CREATE_EVENT_PRESENT)
      jq -c '.events += [{seq:(.events | length),operation:"create_agent",callCount:1,requestPath:"/fixture/mcp-create.json",transport:"mcp__paseo__create_agent"}]' \
        "$reentry_attempt/call-log.json" > "$reentry_attempt/call-log.tmp"
      mv "$reentry_attempt/call-log.tmp" "$reentry_attempt/call-log.json"
      chmod 600 "$reentry_attempt/call-log.json" ;;
    NON_CONTIGUOUS_SEQ)
      jq -c '.events[-1].seq += 3' "$reentry_attempt/call-log.json" > "$reentry_attempt/call-log.tmp"
      mv "$reentry_attempt/call-log.tmp" "$reentry_attempt/call-log.json"
      chmod 600 "$reentry_attempt/call-log.json" ;;
    UNKNOWN_LOG_KEY)
      jq -c '.events[-1].unknown = true' "$reentry_attempt/call-log.json" > "$reentry_attempt/call-log.tmp"
      mv "$reentry_attempt/call-log.tmp" "$reentry_attempt/call-log.json"
      chmod 600 "$reentry_attempt/call-log.json" ;;
  esac
  reentry_state_before="$(cat "$reentry_attempt/state.json")"
  reentry_log_before="$(cat "$reentry_attempt/call-log.json")"
  out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" --attempt-dir "$reentry_attempt" \
    --call-log "$reentry_attempt/call-log.json" --adapter "$SUCCESS_ADAPTER" --response "$accepted_response" \
    --wait-timeout 1200 2>/dev/null)"
  assert_eq "$?" "2" "MAD 受理前検査: $reentry_case は exit 2"
  assert_eq "$out" "" "MAD 受理前検査: $reentry_case は stdout を出さない"
  assert_eq "$(cat "$reentry_attempt/state.json")" "$reentry_state_before" \
    "MAD 受理前検査: $reentry_case は state を変更しない"
  assert_eq "$(cat "$reentry_attempt/call-log.json")" "$reentry_log_before" \
    "MAD 受理前検査: $reentry_case は call log を変更しない"
done

# marker が無い attempt で --exercise-accepted は marker を作らない。
assert_eq "$(test -e "$TMP/mad-reentry-MISSING_MARKER/mcp-create.prepared" && echo yes || echo no)" "no" \
  "MAD 受理前検査: --exercise-accepted は prepare marker を新規作成しない"

# 親の MCP 境界は create の直前に request を strict 検証する。runner がその assertion を公開する。
bash "$MAD_RUNNER" --assert-create-request --share-dir "$SHARE" --attempt-dir "$attempt" >/dev/null 2>&1
assert_eq "$?" "0" "pre-create assertion: 検証済み request を受理する"
for pre_create_case in EXTRA_KEY NON_AUTO_MODE UNLISTED_FEATURE WORLD_READABLE; do
  pre_create_attempt="$TMP/mad-pre-create-$pre_create_case"
  make_pre_create_attempt "$attempt" "$pre_create_attempt"
  case "$pre_create_case" in
    EXTRA_KEY) jq -c '. + {version:1}' "$attempt/mcp-create.json" > "$pre_create_attempt/mcp-create.json" ;;
    NON_AUTO_MODE) jq -c '.settings.modeId = "manual"' "$attempt/mcp-create.json" > "$pre_create_attempt/mcp-create.json" ;;
    UNLISTED_FEATURE) jq -c '.settings.features.verbose = true' "$attempt/mcp-create.json" > "$pre_create_attempt/mcp-create.json" ;;
    WORLD_READABLE) cp "$attempt/mcp-create.json" "$pre_create_attempt/mcp-create.json" ;;
  esac
  if [ "$pre_create_case" = WORLD_READABLE ]; then
    chmod 644 "$pre_create_attempt/mcp-create.json"
  else
    chmod 600 "$pre_create_attempt/mcp-create.json"
  fi
  pre_create_state_before="$(cat "$pre_create_attempt/state.json")"
  out="$(bash "$MAD_RUNNER" --assert-create-request --share-dir "$SHARE" \
    --attempt-dir "$pre_create_attempt" 2>/dev/null)"
  assert_eq "$?" "2" "pre-create assertion: $pre_create_case は exit 2"
  assert_eq "$out" "" "pre-create assertion: $pre_create_case は stdout を出さない"
  assert_eq "$(cat "$pre_create_attempt/state.json")" "$pre_create_state_before" \
    "pre-create assertion: $pre_create_case は state を変更しない"

  # 親の MCP 境界は assertion を通す前に create を観測しない。
  pre_create_observed="$TMP/pre-create-observed-$pre_create_case.json"
  pre_create_response="$TMP/pre-create-response-$pre_create_case.json"
  PASEO_MAD_VALIDATOR="$MAD_RUNNER" PASEO_MAD_SHARE_DIR="$SHARE" \
    PASEO_FAKE_MCP_OBSERVED="$pre_create_observed" bash "$CREATE_BOUNDARY" \
    --request "$pre_create_attempt/mcp-create.json" --response-out "$pre_create_response" 2>/dev/null
  assert_eq "$([ "$?" -ne 0 ] && printf yes || printf no)" "yes" \
    "MCP 境界: $pre_create_case を accepted にしない"
  assert_eq "$(test -e "$pre_create_observed" && echo yes || echo no)" "no" \
    "MCP 境界: $pre_create_case の create 観測を残さない"
  assert_eq "$(test -e "$pre_create_response" && echo yes || echo no)" "no" \
    "MCP 境界: $pre_create_case の accepted response を書かない"
  assert_eq "$(test -e "$pre_create_attempt/mcp-create.prepared" && echo yes || echo no)" "no" \
    "MCP 境界: $pre_create_case は prepare marker を残さない"
done

# 検証を通らない request では state を進めない。
for tampered_case in EXTRA_KEY NON_AUTO_MODE UNLISTED_FEATURE WORLD_READABLE; do
  tampered_attempt="$TMP/mad-tampered-$tampered_case"
  make_pre_create_attempt "$attempt" "$tampered_attempt"
  write_prepare_marker "$tampered_attempt/mcp-create.prepared"
  case "$tampered_case" in
    EXTRA_KEY) jq -c '. + {version:1}' "$attempt/mcp-create.json" > "$tampered_attempt/mcp-create.json" ;;
    NON_AUTO_MODE) jq -c '.settings.modeId = "manual"' "$attempt/mcp-create.json" > "$tampered_attempt/mcp-create.json" ;;
    UNLISTED_FEATURE) jq -c '.settings.features.verbose = true' "$attempt/mcp-create.json" > "$tampered_attempt/mcp-create.json" ;;
    WORLD_READABLE) cp "$attempt/mcp-create.json" "$tampered_attempt/mcp-create.json"; chmod 644 "$tampered_attempt/mcp-create.json" ;;
  esac
  [ "$tampered_case" = WORLD_READABLE ] || chmod 600 "$tampered_attempt/mcp-create.json"
  out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" --attempt-dir "$tampered_attempt" \
    --call-log "$tampered_attempt/call-log.json" --adapter "$SUCCESS_ADAPTER" --response "$accepted_response" \
    --wait-timeout 1200 2>/dev/null)"
  assert_eq "$?" "2" "MAD 未検証 request: $tampered_case は exit 2"
  assert_eq "$out" "" "MAD 未検証 request: $tampered_case は stdout を出さない"
  assert_eq "$(jq -c '[.events[] | select(.operation == "create_agent")]' "$tampered_attempt/call-log.json")" '[]' \
    "MAD 未検証 request: $tampered_case は create を記録しない"
  assert_eq "$(jq -r '.state' "$tampered_attempt/state.json")" "failed" \
    "MAD 未検証 request: $tampered_case は failed state にする"
  assert_eq "$(jq -r '.create_accepted' "$tampered_attempt/state.json")" "false" \
    "MAD 未検証 request: $tampered_case は create 未受理のままにする"
done

for invalid_child_ref_case in DUPLICATE_ACCEPTED_CHILD_REF PROTO_CHILD_REF DOT_CHILD_REF REJECT; do
  invalid_child_ref_attempt="$TMP/mad-invalid-child-ref-$invalid_child_ref_case"
  make_pre_create_attempt "$attempt" "$invalid_child_ref_attempt"
  case "$invalid_child_ref_case" in
    DUPLICATE_ACCEPTED_CHILD_REF) invalid_child_ref_env=PASEO_FAKE_DUPLICATE_ACCEPTED_CHILD_REF ;;
    PROTO_CHILD_REF) invalid_child_ref_env=PASEO_FAKE_PROTO_CHILD_REF ;;
    DOT_CHILD_REF) invalid_child_ref_env=PASEO_FAKE_DOT_CHILD_REF ;;
    REJECT) invalid_child_ref_env=PASEO_FAKE_MCP_REJECT ;;
  esac
  invalid_child_ref_response="$TMP/mcp-response-$invalid_child_ref_case.json"
  env "$invalid_child_ref_env=1" PASEO_MAD_SHARE_DIR="$SHARE" bash "$CREATE_BOUNDARY" \
    --request "$invalid_child_ref_attempt/mcp-create.json" --response-out "$invalid_child_ref_response"
  out="$(bash "$MAD_RUNNER" --exercise-accepted --share-dir "$SHARE" \
    --attempt-dir "$invalid_child_ref_attempt" --call-log "$invalid_child_ref_attempt/call-log.json" \
    --adapter "$SUCCESS_ADAPTER" --response "$invalid_child_ref_response" --wait-timeout 1200 2>/dev/null)"
  assert_eq "$?" "1" "MAD childRef: $invalid_child_ref_case を create failure にする"
  assert_eq "$out" "" "MAD childRef: $invalid_child_ref_case は stdout を出さない"
  assert_eq "$(jq -r '.state' "$invalid_child_ref_attempt/state.json")" "failed" \
    "MAD childRef: $invalid_child_ref_case は failed state にする"
  assert_eq "$(jq -r 'has("child_ref")' "$invalid_child_ref_attempt/state.json")" "false" \
    "MAD childRef: $invalid_child_ref_case を state に保存しない"
  assert_eq "$(jq -r '.create_accepted' "$invalid_child_ref_attempt/state.json")" "false" \
    "MAD childRef: $invalid_child_ref_case は create 未受理を記録する"
  assert_eq "$(jq '[.events[] | select(.operation == "create_agent")] | length' "$invalid_child_ref_attempt/call-log.json")" "1" \
    "MAD childRef: $invalid_child_ref_case は create を一回だけ記録して retry しない"
  assert_eq "$(jq -r '.events[-1] | "\(.operation) \(.stage) \(.createCalls) \(.state)"' "$invalid_child_ref_attempt/call-log.json")" \
    "failure create_agent 1 failed" "MAD childRef: $invalid_child_ref_case の終端 event"
  assert_eq "$(test -e "$invalid_child_ref_attempt/wait-evidence.json" && echo yes || echo no)" "no" \
    "MAD childRef: $invalid_child_ref_case は wait を呼ばない"
done

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
assert_eq "$(test -e "$broken_attempt/mcp-create.json" && echo yes || echo no)" "no" \
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
  assert_eq "$(test -e "$dir/mcp-create.json" && echo yes || echo no)" "no" "MAD 失敗 $stage: request を作らない"
  assert_eq "$(jq -r '.state' "$dir/state.json")" "$expected_state" "MAD 失敗 $stage: state は $expected_state"
  assert_eq "$(jq -r '.create_accepted' "$dir/state.json")" "false" \
    "MAD 失敗 $stage: create 未受理を記録する"
  MAD_CONTRACT="$MAD_CONTRACT" CALL_LOG="$dir/call-log.json" node -e '
    const fs = require("node:fs")
    require(process.env.MAD_CONTRACT).assertMadCallLogV1(JSON.parse(fs.readFileSync(process.env.CALL_LOG, "utf8")))
  ' >/dev/null 2>&1
  assert_eq "$?" "0" "MAD 失敗 $stage: 終端 event も call log schema を満たす"
}
fail_case discovery "$MAD_FIXTURES/adapter/fake-discovery-failure-adapter.sh" task-reviewer "$VALID" 2 waiting_for_user
fail_case list_models "$MAD_FIXTURES/adapter/fake-list-models-failure-adapter.sh" task-reviewer "$VALID" 2 waiting_for_user
fail_case resolve "$SUCCESS_ADAPTER" task-reviewer "$FIXTURES/exhausted-v1.json" 4 waiting_for_user

exhausted_attempt="$TMP/mad-fail-resolve"
assert_eq "$(test -f "$exhausted_attempt/launch.json" && echo yes || echo no)" "yes" \
  "MAD exhausted resolve: launch failure を保存する"
assert_eq "$(jq -c 'keys | sort' "$exhausted_attempt/launch.json")" \
  '["candidates","environment","profileName","reasonCode","status","tier","type","version","warnings"]' \
  "MAD exhausted resolve: launch failure の key set"
assert_eq "$(jq -r '.type' "$exhausted_attempt/launch.json")" "mad-launch-failure" \
  "MAD exhausted resolve: launch failure の discriminator"
assert_eq "$(jq -r '.reasonCode' "$exhausted_attempt/launch.json")" "candidates_exhausted" \
  "MAD exhausted resolve: launch failure の reasonCode"
assert_eq "$(jq -r '.candidates | type' "$exhausted_attempt/launch.json")" "array" \
  "MAD exhausted resolve: launch failure の candidates"
assert_eq "$(jq -r '[.candidates[] | (.reasonCode as $reason | ["provider_missing_from_snapshot","provider_unavailable","auto_mode_unavailable","model_unavailable","thinking_option_unavailable"] | index($reason) != null)] | all' "$exhausted_attempt/launch.json")" "true" \
  "MAD exhausted resolve: candidate reasonCode は許可した5値のいずれか"

# runner 自身は create の transport を持たない。source に create の呼び出しを残さない。
runner_source="$(cat "$MAD_RUNNER")"
assert_not_contains "$runner_source" 'create-agent --request' \
  "MAD runner: adapter の create subcommand を呼ばない"
wait_timeout_dir="$TMP/mad-exercise-success-wait-timeout"
mkdir -p "$wait_timeout_dir"
bash "$MAD_RUNNER" --exercise-success \
  --generator "$GENERATOR" --share-dir "$SHARE" --input "$VALID" --adapter "$SUCCESS_ADAPTER" \
  --attempt-dir "$wait_timeout_dir" --project "$NON_GIT_DIR" --role task-reviewer \
  --provenance mad-dispatch --title 'fixture title' --workspace-id fixture-workspace \
  --initial-prompt 'fixture prompt' --notify-on-finish true --wait-timeout 1200 \
  --call-log "$wait_timeout_dir/call-log.json" >/dev/null 2>&1
assert_eq "$?" "2" "MAD runner: exercise-success は wait-timeout を受け付けない"
assert_contains "$runner_source" 'mcp-create.json' \
  "MAD runner: request file を mcp-create.json という名前で書く"

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
  if [ "${PASEO_FAKE_REAL_PROVIDER_SHAPE_CAPITALIZED:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":"Plan Mode, Always Ask, Accept File Edits, Auto mode, Bypass"},{"provider":"codex-lab","status":"unavailable","enabled":"Disabled","label":"Codex Lab","defaultMode":"none","modes":""}]'
  elif [ "${PASEO_FAKE_REAL_CODEX_MODE_LABELS:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"claude","status":"available","enabled":"Enabled","label":"Claude","defaultMode":"auto","modes":"Plan Mode, Always Ask, Accept File Edits, Auto mode, Bypass"},{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":"Default Permissions, Auto-review, Full Access"}]'
  elif [ "${PASEO_FAKE_REAL_OPENCODE_MODE_LABELS:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"claude","status":"available","enabled":"Enabled","label":"Claude","defaultMode":"auto","modes":"Plan Mode, Always Ask, Accept File Edits, Auto mode, Bypass"},{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":"Default Permissions, Auto-review, Full Access"},{"provider":"opencode","status":"available","enabled":"Enabled","label":"OpenCode","defaultMode":"auto","modes":"Build, Plan"}]'
  elif [ "${PASEO_FAKE_REAL_OPENCODE_UNKNOWN_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"opencode","status":"available","enabled":"Enabled","label":"OpenCode","defaultMode":"auto","modes":"Build, Plan, Unknown Mode"}]'
  elif [ "${PASEO_FAKE_REAL_OPENCODE_MISSING_MODES:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"opencode","status":"available","enabled":"Enabled","label":"OpenCode","defaultMode":"auto"}]'
  elif [ "${PASEO_FAKE_REAL_OPENCODE_DUPLICATE_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"opencode","status":"available","enabled":"Enabled","label":"OpenCode","defaultMode":"auto","modes":"Build, Plan, Build"}]'
  elif [ "${PASEO_FAKE_REAL_OPENCODE_BAD_MODE_TYPE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"opencode","status":"available","enabled":"Enabled","label":"OpenCode","defaultMode":"auto","modes":["Build","Plan"]}]'
  elif [ "${PASEO_FAKE_REAL_CODEX_UNKNOWN_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":"Default Permissions, Unknown Mode, Full Access"}]'
  elif [ "${PASEO_FAKE_REAL_CODEX_MISSING_MODES:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto"}]'
  elif [ "${PASEO_FAKE_REAL_CODEX_DUPLICATE_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":"Default Permissions, Default Permissions"}]'
  elif [ "${PASEO_FAKE_REAL_CODEX_BAD_MODE_TYPE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"Enabled","label":"Codex","defaultMode":"auto","modes":["Default Permissions"]}]'
  elif [ "${PASEO_FAKE_REAL_UNKNOWN_ENABLED:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"unknown","label":"Codex","defaultMode":"auto","modes":"Auto mode"}]'
  elif [ "${PASEO_FAKE_REAL_EMPTY_ENABLED:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"","label":"Codex","defaultMode":"auto","modes":"Auto mode"}]'
  elif [ "${PASEO_FAKE_REAL_BAD_ENABLED_TYPE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":true,"label":"Codex","defaultMode":"auto","modes":"Auto mode"}]'
  elif [ "${PASEO_FAKE_REAL_PROVIDER_SHAPE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"enabled","label":"Codex","defaultMode":"auto","modes":"Plan Mode, Always Ask, Accept File Edits, Auto mode, Bypass"},{"provider":"codex-lab","status":"unavailable","enabled":"disabled","label":"Codex Lab","defaultMode":"none","modes":""}]'
  elif [ "${PASEO_FAKE_REAL_MISSING_MODES:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"enabled","label":"Codex","defaultMode":"auto"}]'
  elif [ "${PASEO_FAKE_REAL_UNKNOWN_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"enabled","label":"Codex","defaultMode":"auto","modes":"Plan Mode, Unknown Mode"}]'
  elif [ "${PASEO_FAKE_REAL_DUPLICATE_MODE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"enabled","label":"Codex","defaultMode":"auto","modes":"Auto mode, Auto mode"}]'
  elif [ "${PASEO_FAKE_REAL_BAD_MODE_TYPE:-0}" = "1" ]; then
    printf '%s\n' '[{"provider":"codex","status":"available","enabled":"enabled","label":"Codex","defaultMode":"auto","modes":["Auto mode"]}]'
  elif [ "${PASEO_FAKE_MISSING_UNAVAILABLE_MODE_IDS:-0}" = "1" ]; then
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
  printf '%s\n' "${PASEO_FAKE_RUN_RESPONSE:-{\"agentId\":\"33333333-3333-4333-8333-333333333333\",\"status\":\"running\",\"provider\":\"codex/model\",\"cwd\":\"/private/tmp/paseo\",\"title\":\"fixture title\"}}"
  exit 0
fi
if [ "${1:-}" = "wait" ]; then
  printf '%s\n' "$*" > "$PASEO_FAKE_ARGS"
  printf '%s\n' "${PASEO_FAKE_WAIT_RESPONSE:-{\"agentId\":\"33333333-3333-4333-8333-333333333333\",\"status\":\"idle\",\"message\":\"private activity history\"}}"
  exit 0
fi
if [ "${1:-}" = "stop" ]; then
  printf '%s\n' "$*" > "$PASEO_FAKE_ARGS"
  printf '%s\n' "${PASEO_FAKE_STOP_RESPONSE:-{\"stoppedCount\":1,\"agentIds\":[\"33333333-3333-4333-8333-333333333333\"]}}"
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
real_shape_providers="$(PASEO_FAKE_REAL_PROVIDER_SHAPE=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers)"
assert_eq "$?" "0" "adapter: 実 CLI discovery shape を受理する"
assert_eq "$(printf '%s' "$real_shape_providers" | jq -c '.providers')" \
  '[{"id":"codex","available":true,"modeIds":["plan","default","acceptEdits","auto","bypassPermissions"]},{"id":"codex-lab","available":false,"modeIds":[]}]' \
  "adapter: modes の表示 label を mode ID に正規化する"
capitalized_real_shape_providers="$(PASEO_FAKE_REAL_PROVIDER_SHAPE_CAPITALIZED=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers)"
assert_eq "$?" "0" "adapter: 実 CLI の Enabled/Disabled shape を受理する"
assert_eq "$(printf '%s' "$capitalized_real_shape_providers" | jq -c '.providers')" \
  '[{"id":"codex","available":true,"modeIds":["plan","default","acceptEdits","auto","bypassPermissions"]},{"id":"codex-lab","available":false,"modeIds":[]}]' \
  "adapter: Enabled/Disabled を eligibility に正規化する"
codex_mode_label_providers="$(PASEO_FAKE_REAL_CODEX_MODE_LABELS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers)"
assert_eq "$?" "0" "adapter: Codex の実 CLI mode labels を受理する"
assert_eq "$(printf '%s' "$codex_mode_label_providers" | jq -c '.providers')" \
  '[{"id":"claude","available":true,"modeIds":["plan","default","acceptEdits","auto","bypassPermissions"]},{"id":"codex","available":true,"modeIds":["auto","auto-review","full-access"]}]' \
  "adapter: Claude と Codex の mode labels を共存して正規化する"
opencode_mode_label_providers="$(PASEO_FAKE_REAL_OPENCODE_MODE_LABELS=1 PASEO_CLI="$FAKE_PASEO" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers)"
assert_eq "$?" "0" "adapter: OpenCode の実 CLI mode labels を受理する"
assert_eq "$(printf '%s' "$opencode_mode_label_providers" | jq -c '.providers')" \
  '[{"id":"claude","available":true,"modeIds":["plan","default","acceptEdits","auto","bypassPermissions"]},{"id":"codex","available":true,"modeIds":["auto","auto-review","full-access"]},{"id":"opencode","available":true,"modeIds":["build","plan"]}]' \
  "adapter: Claude、Codex、OpenCode の mode labels を共存して正規化する"
for invalid_opencode_mode in UNKNOWN_MODE MISSING_MODES DUPLICATE_MODE BAD_MODE_TYPE; do
  case "$invalid_opencode_mode" in
    UNKNOWN_MODE) env_name=PASEO_FAKE_REAL_OPENCODE_UNKNOWN_MODE ;;
    MISSING_MODES) env_name=PASEO_FAKE_REAL_OPENCODE_MISSING_MODES ;;
    DUPLICATE_MODE) env_name=PASEO_FAKE_REAL_OPENCODE_DUPLICATE_MODE ;;
    BAD_MODE_TYPE) env_name=PASEO_FAKE_REAL_OPENCODE_BAD_MODE_TYPE ;;
  esac
  env "$env_name=1" PASEO_CLI="$FAKE_PASEO" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
    >/dev/null 2>&1
  assert_eq "$?" "1" "adapter: OpenCode mode labels の $invalid_opencode_mode を discovery failure にする"
done
for invalid_codex_mode in UNKNOWN_MODE MISSING_MODES DUPLICATE_MODE BAD_MODE_TYPE; do
  case "$invalid_codex_mode" in
    UNKNOWN_MODE) env_name=PASEO_FAKE_REAL_CODEX_UNKNOWN_MODE ;;
    MISSING_MODES) env_name=PASEO_FAKE_REAL_CODEX_MISSING_MODES ;;
    DUPLICATE_MODE) env_name=PASEO_FAKE_REAL_CODEX_DUPLICATE_MODE ;;
    BAD_MODE_TYPE) env_name=PASEO_FAKE_REAL_CODEX_BAD_MODE_TYPE ;;
  esac
  env "$env_name=1" PASEO_CLI="$FAKE_PASEO" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
    >/dev/null 2>&1
  assert_eq "$?" "1" "adapter: Codex mode labels の $invalid_codex_mode を discovery failure にする"
done
for invalid_enabled in UNKNOWN_ENABLED EMPTY_ENABLED BAD_ENABLED_TYPE; do
  case "$invalid_enabled" in
    UNKNOWN_ENABLED) env_name=PASEO_FAKE_REAL_UNKNOWN_ENABLED ;;
    EMPTY_ENABLED) env_name=PASEO_FAKE_REAL_EMPTY_ENABLED ;;
    BAD_ENABLED_TYPE) env_name=PASEO_FAKE_REAL_BAD_ENABLED_TYPE ;;
  esac
  env "$env_name=1" PASEO_CLI="$FAKE_PASEO" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
    >/dev/null 2>&1
  assert_eq "$?" "1" "adapter: enabled の $invalid_enabled を discovery failure にする"
done
for invalid_real_shape in MISSING_MODES UNKNOWN_MODE DUPLICATE_MODE BAD_MODE_TYPE; do
  case "$invalid_real_shape" in
    MISSING_MODES) env_name=PASEO_FAKE_REAL_MISSING_MODES ;;
    UNKNOWN_MODE) env_name=PASEO_FAKE_REAL_UNKNOWN_MODE ;;
    DUPLICATE_MODE) env_name=PASEO_FAKE_REAL_DUPLICATE_MODE ;;
    BAD_MODE_TYPE) env_name=PASEO_FAKE_REAL_BAD_MODE_TYPE ;;
  esac
  env "$env_name=1" PASEO_CLI="$FAKE_PASEO" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" list-providers \
    >/dev/null 2>&1
  assert_eq "$?" "1" "adapter: 実 CLI shape の $invalid_real_shape を discovery failure にする"
done
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
ADAPTER="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter"
opaque_request="$TMP/opaque-create-request.json"
jq '.notifyOnFinish = false | .provider = "codex/model/opaque" | .settings.thinkingOptionId = "thinking option"' \
  "$MAD_FIXTURES/create-request-success.json" > "$opaque_request"
chmod 600 "$opaque_request"
# Paseo CLI の run は settings.features を渡す option を持たない。CLI を create の
# 経路にすると feature が黙って落ちるので、adapter から create を外した。
adapter_create_out="$(PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_ARGS="$FAKE_PASEO_ARGS" \
  "$ADAPTER" create-agent --request "$opaque_request" 2>/dev/null)"
assert_eq "$?" "2" "adapter: create-agent subcommand を受け付けない"
assert_eq "$adapter_create_out" "" "adapter: create-agent は response を返さない"
adapter_source="$(cat "$ADAPTER")"
assert_not_contains "$adapter_source" "'run', '--background'" \
  "adapter: paseo run による create 経路を残さない"
assert_not_contains "$adapter_source" 'createAgent' "adapter: create の実装を残さない"
for adapter_command in list-providers list-models wait-agent stop-agent; do
  assert_contains "$adapter_source" "case '$adapter_command':" \
    "adapter: $adapter_command の境界は残す"
done

adapter_wait="$(PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_ARGS="$FAKE_PASEO_ARGS" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
  wait-agent --child-ref 33333333-3333-4333-8333-333333333333 --timeout 30)"
assert_eq "$?" "0" "adapter: accepted childRef を paseo wait へ渡す"
assert_eq "$adapter_wait" '{"status":"idle"}' "adapter: wait response を status だけに縮約する"
assert_eq "$(cat "$FAKE_PASEO_ARGS")" \
  'wait 33333333-3333-4333-8333-333333333333 --timeout 30 --json' \
  "adapter: paseo wait の CLI 契約を使う"
assert_not_contains "$adapter_wait" 'private activity history' "adapter: raw wait response を返さない"
adapter_stop="$(PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" PASEO_FAKE_ARGS="$FAKE_PASEO_ARGS" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
  stop-agent --child-ref 33333333-3333-4333-8333-333333333333)"
assert_eq "$?" "0" "adapter: stop-agent は検証済み stop response を受理する"
assert_eq "$adapter_stop" '{"status":"stopped"}' "adapter: stop response を status だけに縮約する"
assert_eq "$(cat "$FAKE_PASEO_ARGS")" \
  'stop 33333333-3333-4333-8333-333333333333 --json' \
  "adapter: paseo stop の CLI 契約を使う"
assert_not_contains "$adapter_stop" 'agentIds' "adapter: raw stop response を返さない"
for invalid_stop_id in \
  '' \
  '../33333333-3333-4333-8333-333333333333' \
  '/private/tmp/agent' \
  '--all' \
  'has whitespace'; do
  invalid_stop_out="$(PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
    stop-agent --child-ref "$invalid_stop_id" 2>/dev/null)"
  assert_eq "$?" "2" "adapter: 不正な stop childRef を拒否する"
  assert_eq "$invalid_stop_out" "" "adapter: 不正な stop childRef は response を返さない"
done
for invalid_stop_response in \
  '{}' \
  '{"stoppedCount":0,"agentIds":[]}' \
  '{"stoppedCount":1,"agentIds":["other-agent"]}' \
  '{"stoppedCount":1,"agentIds":["33333333-3333-4333-8333-333333333333"],"extra":true}' \
  '{"stoppedCount":1,"agentIds":["33333333-3333-4333-8333-333333333333","33333333-3333-4333-8333-333333333333"]}' \
  '{"stoppedCount":1,"agentIds":["33333333-3333-4333-8333-333333333333"],"stoppedCount":2}'; do
  invalid_stop_out="$(PASEO_FAKE_STOP_RESPONSE="$invalid_stop_response" PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
    stop-agent --child-ref 33333333-3333-4333-8333-333333333333 2>/dev/null)"
  assert_eq "$?" "1" "adapter: 不正な stop response を拒否する"
  assert_eq "$invalid_stop_out" '{"status":"error"}' "adapter: 不正な stop response は sanitized error だけを返す"
  assert_not_contains "$invalid_stop_out" 'other-agent' "adapter: 不正な stop response の raw 値を漏らさない"
done
for invalid_wait_response in \
  '{"status":"idle"}' \
  '{"status":"unknown"}' \
  '{"agentId":"other-agent","status":"idle"}' \
  '{"agentId":"33333333-3333-4333-8333-333333333333","status":"idle","extra":true}' \
  '{"status":"idle","status":"timeout"}' \
  '{"message":"missing status"}'; do
  invalid_wait_out="$(PASEO_FAKE_WAIT_RESPONSE="$invalid_wait_response" PASEO_CLI="$FAKE_PASEO" PASEO_MAD_SHARE_DIR="$SHARE" \
    "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter" \
    wait-agent --child-ref 33333333-3333-4333-8333-333333333333 --timeout 30 2>/dev/null)"
  assert_eq "$?" "1" "adapter: 不正な wait status を拒否する"
  assert_eq "$invalid_wait_out" "" "adapter: 不正な wait response を返さない"
done
# call log の event key set は contract module が持つ。transport は create_agent の必須 key である。
MAD_CONTRACT="$MAD_CONTRACT" SUCCESS_LOG="$attempt/call-log.json" node - <<'NODE'
const fs = require('node:fs')
const contract = require(process.env.MAD_CONTRACT)
const log = JSON.parse(fs.readFileSync(process.env.SUCCESS_LOG, 'utf8'))
contract.assertMadCallLogV1(log)
const createEvent = log.events.find((event) => event.operation === 'create_agent')
if (createEvent.transport !== 'mcp__paseo__create_agent') process.exit(1)
if (Object.keys(createEvent).sort().join(',') !== 'callCount,operation,requestPath,seq,transport') process.exit(1)
const clone = () => JSON.parse(JSON.stringify(log))
const invalid = []
const unknownKey = clone()
unknownKey.events[unknownKey.events.length - 1].unknown = true
invalid.push(unknownKey)
const missingTransport = clone()
delete missingTransport.events.find((event) => event.operation === 'create_agent').transport
invalid.push(missingTransport)
const wrongTransport = clone()
wrongTransport.events.find((event) => event.operation === 'create_agent').transport = 'paseo run'
invalid.push(wrongTransport)
const gapSeq = clone()
gapSeq.events[gapSeq.events.length - 1].seq += 3
invalid.push(gapSeq)
const unknownOperation = clone()
unknownOperation.events[0].operation = 'inspect_agent'
invalid.push(unknownOperation)
const rawUrl = clone()
rawUrl.events.find((event) => event.operation === 'create_agent').requestPath = 'https://example.test/x'
invalid.push(rawUrl)
const extraTopLevel = clone()
extraTopLevel.note = 'extra'
invalid.push(extraTopLevel)
for (const value of invalid) {
  let code = null
  try { contract.assertMadCallLogV1(value) } catch (error) { code = error.code }
  if (code !== 'invalid_mad_call_log') process.exit(1)
}
process.exit(0)
NODE
assert_eq "$?" "0" "contract: call log は event ごとの exact key set と連続 seq を要求する"

# accepted response の strict 検証は contract module が持つ。
MAD_CONTRACT="$MAD_CONTRACT" node - <<'NODE'
const contract = require(process.env.MAD_CONTRACT)
const invalid = [
  '{"status":"accepted"}',
  '{"childRef":"33333333-3333-4333-8333-333333333333"}',
  '{"status":"rejected","childRef":"33333333-3333-4333-8333-333333333333"}',
  '{"status":"accepted","childRef":"33333333-3333-4333-8333-333333333333","extra":true}',
  '{"status":"accepted","childRef":"33333333-3333-4333-8333-333333333333","childRef":"44444444-4444-4444-8444-444444444444"}',
  '{"status":"accepted","childRef":"not/a-safe-agent-id"}',
  '{"status":"accepted","childRef":".."}',
]
for (const raw of invalid) {
  let code = null
  try { contract.assertMadCreateAcceptedResponseV1(raw) } catch (error) { code = error.code }
  if (code !== 'invalid_mad_create_response') process.exit(1)
}
const accepted = contract.assertMadCreateAcceptedResponseV1(
  '{"status":"accepted","childRef":"33333333-3333-4333-8333-333333333333"}')
if (Object.keys(accepted).sort().join(',') !== 'childRef,status') process.exit(1)
process.exit(0)
NODE
assert_eq "$?" "0" "contract: accepted response は exact key set と safe childRef だけを受理する"

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
assert_eq "$(jq -c '[.events[] | select(.operation == "create_agent")]' "$opaque_attempt/call-log.json")" \
  '[]' "MAD opaque mode: runner は create を呼ばない"
assert_eq "$(stat -f '%HT:%Lp' "$opaque_attempt/mcp-create.json")" "Regular File:600" \
  "MAD opaque mode: mcp-create.json は 0600 の regular file"

# --exercise-create は create の transport を持たない。snapshot と launch を検証して
# から 0600 の request を書くだけであり、create 回数は常に 0 である。
for invalid_snapshot in malformed invalid-top-level-key providers-models-key-set-mismatch \
  mode-ids-not-string-array model-entry-not-object; do
  create_log="$TMP/exercise-snapshot-$invalid_snapshot.json"
  request_out="$TMP/exercise-snapshot-$invalid_snapshot-request.json"
  out="$(bash "$MAD_RUNNER" --exercise-create \
    --share-dir "$SHARE" \
    --snapshot "$FIXTURES/snapshots/$invalid_snapshot.json" \
    --launch "$FIXTURES/launch/success.json" --request-out "$request_out" \
    --create-log "$create_log" 2>/dev/null)"
  assert_eq "$?" "2" "exercise-create: $invalid_snapshot は exit 2"
  assert_eq "$out" "" "exercise-create: $invalid_snapshot は stdout を出さない"
  assert_eq "$(jq -r '.createCalls' "$create_log")" "0" "exercise-create: $invalid_snapshot は create 0 回"
  assert_eq "$(test -e "$request_out" && echo yes || echo no)" "no" \
    "exercise-create: $invalid_snapshot は request を書かない"
done
for invalid_launch in exhausted invalid-extra-field invalid-non-auto-mode invalid-unlisted-feature \
  invalid-non-integer-feature; do
  create_log="$TMP/exercise-launch-$invalid_launch.json"
  request_out="$TMP/exercise-launch-$invalid_launch-request.json"
  out="$(bash "$MAD_RUNNER" --exercise-create \
    --share-dir "$SHARE" \
    --snapshot "$FIXTURES/snapshots/all-available.json" \
    --launch "$FIXTURES/launch/$invalid_launch.json" --request-out "$request_out" \
    --create-log "$create_log" 2>/dev/null)"
  assert_eq "$?" "2" "exercise-create: $invalid_launch は exit 2"
  assert_eq "$out" "" "exercise-create: $invalid_launch は stdout を出さない"
  assert_eq "$(jq -r '.createCalls' "$create_log")" "0" "exercise-create: $invalid_launch は create 0 回"
  assert_eq "$(test -e "$request_out" && echo yes || echo no)" "no" \
    "exercise-create: $invalid_launch は request を書かない"
done

create_log="$TMP/exercise-create-success.json"
request_out="$TMP/exercise-create-success-request.json"
out="$(bash "$MAD_RUNNER" --exercise-create \
  --share-dir "$SHARE" --snapshot "$FIXTURES/snapshots/all-available.json" \
  --launch "$FIXTURES/launch/success.json" --request-out "$request_out" \
  --create-log "$create_log" 2>/dev/null)"
assert_eq "$?" "0" "exercise-create: 検証済み launch から request を書く"
assert_eq "$out" "" "exercise-create: stdout を出さない"
assert_eq "$(jq -r '.createCalls' "$create_log")" "0" "exercise-create: 成功時も create 0 回"
assert_eq "$(jq -r '.requestPath' "$create_log")" "$request_out" \
  "exercise-create: 書いた request の path を記録する"
assert_eq "$(stat -f '%HT:%Lp' "$request_out")" "Regular File:600" \
  "exercise-create: request は 0600 の regular file"
assert_eq "$(jq -c 'keys' "$request_out")" \
  '["initialPrompt","notifyOnFinish","provider","settings","title","workspaceId"]' \
  "exercise-create: request は公式 MCP create の 6 引数だけを持つ"

# fast_mode を持つ launch でも、値を落とさずに request へ写す。
fast_mode_launch_file="$TMP/launch-fast-mode.json"
jq -c '.featureValues = {"fast_mode":true}' "$FIXTURES/launch/success.json" > "$fast_mode_launch_file"
create_log="$TMP/exercise-create-fast-mode.json"
request_out="$TMP/exercise-create-fast-mode-request.json"
bash "$MAD_RUNNER" --exercise-create \
  --share-dir "$SHARE" --snapshot "$FIXTURES/snapshots/all-available.json" \
  --launch "$fast_mode_launch_file" --request-out "$request_out" \
  --feature-allowlist '{"fast_mode":"boolean"}' \
  --create-log "$create_log" >/dev/null 2>&1
assert_eq "$?" "0" "exercise-create: fast_mode を持つ launch を受理する"
assert_eq "$(jq -c '.settings.features' "$request_out")" '{"fast_mode":true}' \
  "exercise-create: fast_mode を settings.features へ落とさずに写す"

assert_contains "$(cat "$CHEZMOI_SOURCE/tests/test-distribution.sh")" \
  '.local/share/agent-config/mad-contract.js' "distribution: MAD の契約 module を配る"
assert_contains "$(cat "$CHEZMOI_SOURCE/tests/test-distribution.sh")" \
  '.agents/skills/multi-agent-development/scripts/paseo-mcp-adapter' "distribution: adapter を配る"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
