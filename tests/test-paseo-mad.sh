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
  env -u DECISION_REQUEST_PATH -u PASEO_PLAN_PATH -u PASEO_UNIT3_PLAN_FIXTURE \
  /bin/bash "$UNIT_GATE" record-unit3 >/dev/null 2>&1
unit3_no_plan_status=$?
assert_eq "$([ "$unit3_no_plan_status" -ne 0 ] && printf yes || printf no)" "yes" \
  "unit3: 外側 plan が無ければ continue を拒否する"
assert_contains "$(cat "$UNIT3_NO_PLAN/unit3-failure.txt" 2>/dev/null)" "plan-dependency(exit 2)" \
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
  create-agent)
    [ "${2:-}" = "--request" ] || exit 2
    request_path="${3:-}"
    jq -e '
      .provider == "codex/live-model" and
      .workspaceId == "live-workspace" and
      .settings.thinkingOptionId == "live-thinking"
    ' "$request_path" >/dev/null || exit 2
    prompt="$(jq -r '.initialPrompt' "$request_path")"
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
    printf '%s\n' '{"status":"accepted"}'
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$LIVE_PHASE_ADAPTER"

LIVE_ROOT="$TMP/live-root"
mkdir -p "$LIVE_ROOT"
PASEO_MAD_GENERATOR="$GENERATOR" PASEO_MAD_ADAPTER="$LIVE_PHASE_ADAPTER" \
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
