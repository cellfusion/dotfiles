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
    ([.events[].operation] == [
      "enumerate_materialized_provider_ids",
      "list_providers",
      "list_models",
      "list_models",
      "write_snapshot",
      "resolve",
      "build_create_request",
      "create_agent"
    ]) and
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

  for phase in plan implement review fix; do
    result="$evidence_dir/$phase/result.json"
    handoff="$evidence_dir/$phase/handoff.json"
    require_private_regular_file "$result" || return 1
    require_private_regular_file "$handoff" || return 1
    require_json_object "$result" || return 1
    jq -e '.artifact_paths | type == "array" and length > 0 and all(.[]; type == "string" and startswith("/"))' \
      "$handoff" >/dev/null 2>&1 || return 1
    artifact_paths="$(jq -r '.artifact_paths[]' "$handoff" 2>/dev/null)" || return 1
    while IFS= read -r artifact_path; do
      [ -n "$artifact_path" ] || return 1
      [ -f "$artifact_path" ] && [ ! -L "$artifact_path" ] || return 1
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

write_phase_evidence() {
  local evidence_dir="$1"
  local phase="$2"
  local result_path="$evidence_dir/$phase/result.json"
  local result
  local handoff

  case "$phase" in
    plan)
      result="$(jq -cn --arg artifactPath "$result_path" \
        '{status:"ok",artifactPath:$artifactPath,decisionRequestPath:null,summary:"representative plan complete"}')" || return 1
      ;;
    implement)
      result='{"baseHead":"representative-base","changedFiles":["representative.txt"],"summary":"representative implementation complete","decisionRequestPath":null}'
      ;;
    review)
      result='{"specVerdict":"compliant","qualityVerdict":"approved","findings":[],"round":0,"head":"representative-head","packageBase":"representative-base","packageHead":"representative-head","cannotVerify":null,"strengths":"representative review complete"}'
      ;;
    fix)
      result='{"round":1,"head":"representative-head","verdicts":[],"newBreakage":[],"outOfScope":[],"packageBase":"representative-base","packageHead":"representative-head"}'
      ;;
    *) return 1 ;;
  esac

  write_private_file "$result_path" "$result" || return 1
  handoff="$(jq -cn --arg phase "$phase" --arg artifactPath "$result_path" \
    '{run_id:"representative-run",node:$phase,attempt:"ok",artifact_paths:[$artifactPath]}')" || return 1
  write_private_file "$evidence_dir/$phase/handoff.json" "$handoff"
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
  local state_transition
  local evidence

  [ -f "$generator" ] || return 1
  [ -f "$adapter" ] && [ -x "$adapter" ] || return 1
  [ -f "$MAD_RUNNER" ] || return 1
  [ -f "$MAD_CONTRACT" ] || return 1
  [ -f "$FIXTURES/valid-v1.json" ] || return 1
  [ -d "$share_dir" ] || return 1
  [ -L "$evidence_dir" ] && return 1
  mkdir -p "$evidence_dir" || return 1

  RUN_TMP_DIR="$(mktemp -d /tmp/paseo-mad-representative.XXXXXX)" || return 1
  trap 'rm -rf "$RUN_TMP_DIR"' EXIT
  input="$RUN_TMP_DIR/input.json"
  project="$RUN_TMP_DIR/project"
  attempt_dir="$RUN_TMP_DIR/attempt"
  install -m 600 "$FIXTURES/valid-v1.json" "$input" || return 1
  mkdir -p "$project" "$attempt_dir" || return 1

  # Task 8 の成功経路を adapter 経由で一度だけ実行する。adapter の stdout と
  # 実運用の request payload は一時領域に閉じ、証跡の call log には残さない。
  bash "$MAD_RUNNER" --exercise-success \
    --generator "$generator" --share-dir "$share_dir" --input "$input" \
    --adapter "$adapter" --attempt-dir "$attempt_dir" --project "$project" \
    --role implementer --provenance mad-representative \
    --title 'representative title' --workspace-id representative-workspace \
    --initial-prompt 'representative prompt' --notify-on-finish true \
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

  for phase in plan implement review fix; do
    if [ "${MAD_REPRESENTATIVE_FAIL_PHASE:-}" = "$phase" ]; then
      return 1
    fi
    mkdir -p "$evidence_dir/$phase" || return 1
    write_phase_evidence "$evidence_dir" "$phase" || return 1
  done
  state_transition='{"runStates":["running","ok"],"phaseStates":["plan:ok","implement:ok","review:ok","fix:ok"]}'
  write_private_file "$evidence_dir/state-transition.json" "$state_transition" || return 1
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
