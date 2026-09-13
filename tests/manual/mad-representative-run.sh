#!/usr/bin/env bash
# 承認済みの Paseo MAD 代表 run を一度だけ起動し、その証跡を検査する。
set -u

CHEZMOI_SOURCE="$(cd "$(dirname "$0")/../.." && pwd -P)"
. "$CHEZMOI_SOURCE/tests/lib/unit-gate.sh"

FIXTURES="$CHEZMOI_SOURCE/tests/fixtures/agent-config"
MAD_RUNNER="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
MAD_CONTRACT="$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/mad-contract.js"
MAD_EXPORTER="$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/paseo-exporter.js"
DEFAULT_GENERATOR="$CHEZMOI_SOURCE/private_dot_local/bin/executable_generate-paseo-config"
DEFAULT_ADAPTER="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-mcp-adapter"
DEFAULT_DECISION_ROOT="$(printf '/Users/%s/docs/cellfusion/dotfiles/orchestration/paseo-agent-config-migration/evidence' cellfusion)"
VERIFY_ONLY_MODE=0
VERIFY_PLACEHOLDER_DIR=""
RUN_WORKSPACE_ID="representative-workspace"

usage() {
  printf '%s\n' \
    'usage: mad-representative-run.sh --run --evidence-dir <absolute-directory>' \
    '       mad-representative-run.sh --verify-only --evidence-dir <absolute-directory>' >&2
}

require_absolute() {
  case "${2:-}" in
    /*) return 0 ;;
    *) printf 'mad-representative-run: %s must be an absolute path\n' "$1" >&2; return 1 ;;
  esac
}

require_live_override_value() {
  local name="$1"
  local value="$2"

  case "$value" in
    ''|*[[:space:]]*|*[[:cntrl:]]*)
      printf 'mad-representative-run: %s must be a non-empty opaque token\n' "$name" >&2
      return 1
      ;;
  esac
  [ "${#value}" -le 200 ] || {
    printf 'mad-representative-run: %s is too long\n' "$name" >&2
    return 1
  }
}

prepare_run_input() {
  local input="$1"
  local configured=0
  local provider="${PASEO_MAD_REPRESENTATIVE_PROVIDER:-}"
  local model="${PASEO_MAD_REPRESENTATIVE_MODEL:-}"
  local thinking_option="${PASEO_MAD_REPRESENTATIVE_THINKING_OPTION:-}"
  local workspace_id="${PASEO_MAD_REPRESENTATIVE_WORKSPACE_ID:-}"
  local config

  [ "${PASEO_MAD_REPRESENTATIVE_PROVIDER+x}" = x ] && configured=$((configured + 1))
  [ "${PASEO_MAD_REPRESENTATIVE_MODEL+x}" = x ] && configured=$((configured + 1))
  [ "${PASEO_MAD_REPRESENTATIVE_THINKING_OPTION+x}" = x ] && configured=$((configured + 1))
  [ "${PASEO_MAD_REPRESENTATIVE_WORKSPACE_ID+x}" = x ] && configured=$((configured + 1))
  if [ "$configured" -eq 0 ]; then
    install -m 600 "$FIXTURES/valid-v1.json" "$input"
    return
  fi
  [ "$configured" -eq 4 ] || {
    printf '%s\n' 'mad-representative-run: live override requires provider, model, thinking option, and workspace ID' >&2
    return 1
  }
  [ "$provider" = 'codex' ] || {
    printf '%s\n' 'mad-representative-run: live override provider must be codex' >&2
    return 1
  }
  require_live_override_value PASEO_MAD_REPRESENTATIVE_MODEL "$model" || return 1
  require_live_override_value PASEO_MAD_REPRESENTATIVE_THINKING_OPTION "$thinking_option" || return 1
  require_live_override_value PASEO_MAD_REPRESENTATIVE_WORKSPACE_ID "$workspace_id" || return 1

  config="$(jq -c --arg model "$model" --arg thinkingOption "$thinking_option" '
    .providers = {codex: .providers.codex} |
    .tiers |= with_entries(
      .value.candidates = [{
        provider: "codex",
        model: $model,
        thinkingOptionId: $thinkingOption,
        featureValues: {}
      }]
    ) |
    .environments = {primary: {providers: ["codex"], tiers: {}}} |
    .defaults = {environment: "primary", tier: "work"} |
    .projectRouting = {rules: []}
  ' "$FIXTURES/valid-v1.json" 2>/dev/null)" || return 1
  write_private_file "$input" "$config" || return 1
  RUN_WORKSPACE_ID="$workspace_id"
}

write_private_file() {
  local file="$1"
  local value="$2"
  local directory
  local basename
  local temporary

  require_absolute file "$file" || return 1
  directory="$(dirname "$file")"
  basename="$(basename "$file")"
  [ -d "$directory" ] || return 1
  [ -L "$file" ] && return 1
  [ -d "$file" ] && return 1
  temporary="$(mktemp "$directory/.${basename}.tmp.XXXXXX")" || return 1
  if ! ( umask 077; printf '%s' "$value" > "$temporary"; chmod 600 "$temporary" ); then
    rm -f "$temporary"
    return 1
  fi
  if ! mv "$temporary" "$file"; then
    rm -f "$temporary"
    return 1
  fi
}

require_private_regular_file() {
  local file="$1"
  [ -f "$file" ] && [ ! -L "$file" ] || return 1
  [ "$(stat -f '%Lp' "$file" 2>/dev/null)" = "600" ] || return 1
}

require_json_object() {
  local file="$1"
  jq -e 'type == "object"' "$file" >/dev/null 2>&1
}

cleanup_verify_placeholders() {
  [ -n "$VERIFY_PLACEHOLDER_DIR" ] || return 0
  rm -rf "$VERIFY_PLACEHOLDER_DIR"
  VERIFY_PLACEHOLDER_DIR=""
}

resolve_artifact_path() {
  local artifact_path="$1"
  local placeholder=""
  local temporary

  case "$artifact_path" in
    /fixture/plan-result.json) placeholder="plan-result.json" ;;
    /fixture/implement-result.json) placeholder="implement-result.json" ;;
    /fixture/review-result.json) placeholder="review-result.json" ;;
    /fixture/fix-result.json) placeholder="fix-result.json" ;;
    /*) printf '%s\n' "$artifact_path"; return 0 ;;
    *) return 1 ;;
  esac
  [ "$VERIFY_ONLY_MODE" -eq 1 ] || return 1
  if [ -z "$VERIFY_PLACEHOLDER_DIR" ]; then
    VERIFY_PLACEHOLDER_DIR="$(mktemp -d /tmp/mad-representative-verify.XXXXXX)" || return 1
  fi
  temporary="$VERIFY_PLACEHOLDER_DIR/$placeholder"
  if [ ! -e "$temporary" ]; then
    ( umask 077; printf 'anonymous fixture artifact\n' > "$temporary"; chmod 600 "$temporary" ) || return 1
  fi
  [ -f "$temporary" ] && [ ! -L "$temporary" ] || return 1
  printf '%s\n' "$temporary"
}

verify_core_evidence() {
  local evidence_dir="$1"
  local snapshot="$evidence_dir/snapshot.json"
  local launch="$evidence_dir/launch.json"
  local create_call="$evidence_dir/create-call.json"
  local call_log="$evidence_dir/call-log.json"
  local state_transition="$evidence_dir/state-transition.json"

  node - "$MAD_CONTRACT" "$MAD_EXPORTER" "$snapshot" "$launch" "$create_call" <<'NODE' >/dev/null 2>&1
const fs = require('node:fs')
const util = require('node:util')

const contract = require(process.argv[2])
const exporter = require(process.argv[3])
const read = (file) => JSON.parse(fs.readFileSync(file, 'utf8'))

const snapshot = read(process.argv[4])
const launch = read(process.argv[5])
const createCall = read(process.argv[6])
exporter.assertAvailabilitySnapshot(snapshot)
contract.assertMadLaunchSpecV1(launch, {})

if (Object.keys(createCall).sort().join(',') !== 'create_calls,request' || createCall.create_calls !== 1) {
  process.exit(1)
}
contract.assertMadCreateRequestV1(createCall.request, {})
if (createCall.request.provider !== launch.provider + '/' + launch.model ||
    createCall.request.settings.modeId !== 'auto' ||
    createCall.request.settings.thinkingOptionId !== launch.thinkingOptionId ||
    !util.isDeepStrictEqual(createCall.request.settings.features, launch.featureValues)) {
  process.exit(1)
}
NODE

  jq -e '
    type == "object" and
    (keys | sort) == ["events", "type", "version"] and
    .version == 1 and .type == "mad-call-log" and
    (.events | type == "array" and length > 0) and
    ([.events[].operation] as $operations |
      ($operations | length >= 7) and
      $operations[0] == "enumerate_materialized_provider_ids" and
      $operations[1] == "list_providers" and
      ($operations[2:-4] | length > 0 and all(.[]; . == "list_models")) and
      $operations[-4:] == ["write_snapshot", "resolve", "build_create_request", "create_agent"]
    ) and
    ([.events[] | select(.operation == "create_agent") | .callCount] == [1]) and
    (tostring | contains("://") | not)
  ' "$call_log" >/dev/null 2>&1 || return 1

  jq -e '
    type == "object" and
    (keys | sort) == ["phaseStates", "runStates"] and
    .runStates == ["running", "ok"] and
    .phaseStates == ["plan:ok", "implement:ok", "review:ok", "fix:ok"]
  ' "$state_transition" >/dev/null 2>&1 || return 1
}

verify_phase_evidence() {
  local evidence_dir="$1"
  local phase
  local result
  local handoff
  local artifact_paths
  local artifact_path
  local result_artifact
  local resolved_artifact

  for phase in plan implement review fix; do
    result="$evidence_dir/$phase/result.json"
    handoff="$evidence_dir/$phase/handoff.json"
    require_private_regular_file "$result" || return 1
    require_private_regular_file "$handoff" || return 1
    require_json_object "$result" || return 1
    jq -e 'if has("artifactPath") then (.artifactPath | type == "string" and startswith("/")) else true end' \
      "$result" >/dev/null 2>&1 || return 1
    result_artifact="$(jq -r '.artifactPath // empty' "$result" 2>/dev/null)" || return 1
    if [ -n "$result_artifact" ]; then
      resolved_artifact="$(resolve_artifact_path "$result_artifact")" || return 1
      require_private_regular_file "$resolved_artifact" || return 1
    fi
    jq -e --arg phase "$phase" '
      type == "object" and
      (.run_id | type == "string" and length > 0) and
      .node == $phase and
      (.attempt | type == "string" and length > 0) and
      (.artifact_paths | type == "array" and length > 0 and
        all(.[]; type == "string" and startswith("/")))
    ' \
      "$handoff" >/dev/null 2>&1 || return 1
    artifact_paths="$(jq -r '.artifact_paths[]' "$handoff" 2>/dev/null)" || return 1
    while IFS= read -r artifact_path; do
      [ -n "$artifact_path" ] || return 1
      resolved_artifact="$(resolve_artifact_path "$artifact_path")" || return 1
      require_private_regular_file "$resolved_artifact" || return 1
    done <<< "$artifact_paths"
  done
}

verify_evidence() {
  local evidence_dir="$1"
  local evidence

  require_absolute --evidence-dir "$evidence_dir" || return 1
  [ -d "$evidence_dir" ] && [ ! -L "$evidence_dir" ] || return 1
  for evidence in snapshot.json launch.json create-call.json call-log.json state-transition.json \
    plan/result.json plan/handoff.json implement/result.json implement/handoff.json \
    review/result.json review/handoff.json fix/result.json fix/handoff.json; do
    require_private_regular_file "$evidence_dir/$evidence" || return 1
  done
  verify_core_evidence "$evidence_dir" || return 1
  verify_phase_evidence "$evidence_dir" || return 1
}

phase_evidence_ready() {
  local evidence_dir="$1"
  local phase

  for phase in plan implement review fix; do
    require_private_regular_file "$evidence_dir/$phase/result.json" || return 1
    require_private_regular_file "$evidence_dir/$phase/handoff.json" || return 1
  done
  require_private_regular_file "$evidence_dir/state-transition.json" || return 1
  verify_evidence "$evidence_dir" >/dev/null 2>&1
}

wait_for_phase_evidence() {
  local evidence_dir="$1"
  local timeout_seconds="${MAD_REPRESENTATIVE_PHASE_TIMEOUT_SECONDS:-600}"
  local started
  local now

  case "$timeout_seconds" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$timeout_seconds" -le 600 ] || return 1
  started="$(date -u '+%s')" || return 1
  while ! phase_evidence_ready "$evidence_dir"; do
    now="$(date -u '+%s')" || return 1
    [ "$((now - started))" -lt "$timeout_seconds" ] || return 1
    sleep 1
  done
}

write_run_evidence() {
  local evidence_dir="$1"
  local generator="${PASEO_MAD_GENERATOR:-$DEFAULT_GENERATOR}"
  local adapter="${PASEO_MAD_ADAPTER:-$DEFAULT_ADAPTER}"
  local share_dir="${PASEO_MAD_SHARE_DIR:-$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config}"
  local input
  local project
  local attempt_dir
  local request_raw
  local create_call
  local call_log
  local phase
  local evidence
  local phase_prompt

  [ -f "$generator" ] || return 1
  [ -f "$adapter" ] && [ -x "$adapter" ] || return 1
  [ -f "$MAD_RUNNER" ] || return 1
  [ -f "$MAD_CONTRACT" ] || return 1
  [ -f "$FIXTURES/valid-v1.json" ] || return 1
  [ -d "$share_dir" ] || return 1
  [ -L "$evidence_dir" ] && return 1
  mkdir -p "$evidence_dir" || return 1
  [ -z "$(find "$evidence_dir" -mindepth 1 -print -quit)" ] || return 1

  RUN_TMP_DIR="$(mktemp -d /tmp/paseo-mad-representative.XXXXXX)" || return 1
  trap 'rm -rf "$RUN_TMP_DIR"' EXIT
  input="$RUN_TMP_DIR/input.json"
  project="$RUN_TMP_DIR/project"
  attempt_dir="$RUN_TMP_DIR/attempt"
  prepare_run_input "$input" || return 1
  mkdir -p "$project" "$attempt_dir" || return 1
  for phase in plan implement review fix; do
    mkdir -p "$evidence_dir/$phase" || return 1
  done
  phase_prompt="$(printf '%s\n' \
    'Run the representative Paseo MAD delivery phases in order: plan, implement, review, fix.' \
    'Use the plan-author, implementer, task-reviewer, and re-reviewer role prompts and schemas from the repository.' \
    'Write each structured result and handoff atomically as a 0600 regular file, include run_id, node, attempt, and artifact_paths in every handoff, and stop if a phase fails.' \
    "plan result: $evidence_dir/plan/result.json" \
    "plan handoff: $evidence_dir/plan/handoff.json" \
    "implement result: $evidence_dir/implement/result.json" \
    "implement handoff: $evidence_dir/implement/handoff.json" \
    "review result: $evidence_dir/review/result.json" \
    "review handoff: $evidence_dir/review/handoff.json" \
    "fix result: $evidence_dir/fix/result.json" \
    "fix handoff: $evidence_dir/fix/handoff.json" \
    "state transition: $evidence_dir/state-transition.json")" || return 1

  # Task 8 の成功経路を adapter 経由で一度だけ実行する。phase artifact は
  # create 後に child が実際に書いたものを取得し、runner は固定結果を生成しない。
  bash "$MAD_RUNNER" --exercise-success \
    --generator "$generator" --share-dir "$share_dir" --input "$input" \
    --adapter "$adapter" --attempt-dir "$attempt_dir" --project "$project" \
    --role implementer --provenance mad-representative \
    --title 'representative title' --workspace-id "$RUN_WORKSPACE_ID" \
    --initial-prompt "$phase_prompt" --notify-on-finish true \
    --call-log "$attempt_dir/call-log.json" >/dev/null 2>&1 || return 1

  for evidence in snapshot.json launch.json; do
    write_private_file "$evidence_dir/$evidence" "$(jq -c . "$attempt_dir/$evidence" 2>/dev/null)" || return 1
  done
  request_raw="$(jq -c . "$attempt_dir/create-request.json" 2>/dev/null)" || return 1
  [ -n "$request_raw" ] || return 1
  create_call="$(jq -cn --argjson request "$request_raw" '{create_calls:1,request:$request}')" || return 1
  write_private_file "$evidence_dir/create-call.json" "$create_call" || return 1
  call_log="$(jq -c 'if .events then .events |= map(if .operation == "create_agent" then del(.payload) else . end) else . end' \
    "$attempt_dir/call-log.json" 2>/dev/null)" || return 1
  write_private_file "$evidence_dir/call-log.json" "$call_log" || return 1

  wait_for_phase_evidence "$evidence_dir" || return 1
  verify_evidence "$evidence_dir"
}

write_failure_request() {
  local request_path="$1"
  local stage="${2:-代表 run}"
  write_decision_request "$request_path" \
    "Paseo の代表 run が ${stage} で失敗した。後続の phase と削除を停止する" \
    '原因を確認して代表 run を再実行する' \
    '承認せず旧 asset を残す' || true
}

if [ "$#" -ne 3 ] || { [ "${1:-}" != "--run" ] && [ "${1:-}" != "--verify-only" ]; } ||
   [ "${2:-}" != "--evidence-dir" ]; then
  usage
  exit 2
fi

MODE="$1"
EVIDENCE_DIR="$3"
require_absolute --evidence-dir "$EVIDENCE_DIR" || exit 2

if [ "$MODE" = "--verify-only" ]; then
  VERIFY_ONLY_MODE=1
  trap cleanup_verify_placeholders EXIT
  verify_evidence "$EVIDENCE_DIR"
  exit $?
fi

DECISION_REQUEST_PATH="${DECISION_REQUEST_PATH:-$EVIDENCE_DIR/representative-decision-request.md}"
if ! test "${MAD_REPRESENTATIVE_RUN_APPROVED:-0}" = 1; then
  write_failure_request "$DECISION_REQUEST_PATH" '承認されていない代表 run'
  exit 1
fi

DECISION_ROOT="${PASEO_MIGRATION_EVIDENCE_DIR:-$DEFAULT_DECISION_ROOT}"
require_absolute PASEO_MIGRATION_EVIDENCE_DIR "$DECISION_ROOT" || {
  write_failure_request "$DECISION_REQUEST_PATH" '証跡 directory'
  exit 1
}
DECISION_FILE="$DECISION_ROOT/representative-decision.txt"

if write_run_evidence "$EVIDENCE_DIR"; then
  if write_unit_decision "$DECISION_FILE" approved-success; then
    exit 0
  fi
  write_failure_request "$DECISION_REQUEST_PATH" '判定 file'
  exit 1
fi

write_failure_request "$DECISION_REQUEST_PATH" 'Paseo adapter、launch、create、または phase'
exit 1
