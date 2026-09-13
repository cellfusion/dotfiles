#!/usr/bin/env bash
# unit ごとの受け入れを実行し、判定 file を書く。gate の判定を要求する検査は
# tests/test-*.sh に置かず、この runner だけが持つ。
set -u
CHEZMOI_SOURCE="$(cd "$(dirname "$0")/../.." && pwd)"
. "$CHEZMOI_SOURCE/tests/lib/unit-gate.sh"
EVIDENCE="${PASEO_MIGRATION_EVIDENCE_DIR:-$(printf '/Users/%s/docs/cellfusion/dotfiles/orchestration/paseo-agent-config-migration/evidence' cellfusion)}"
cd "$CHEZMOI_SOURCE" || exit 2

record() {
  local decision_file="$1"; shift
  local suite suite_output
  if suite_output="$("$@" 2>&1)"; then
    suite=0
  else
    suite=$?
  fi
  printf '%s\n' "$suite_output"
  if [ "$suite" -eq 0 ] && ! printf '%s\n' "$suite_output" | awk '
    $1 == "SUMMARY" { count += 1; if ($3 != "0") failed = 1 }
    END { exit count == 0 || failed }
  '; then
    suite=1
  fi
  if [ "$suite" -eq 0 ]; then
    write_unit_decision "$EVIDENCE/$decision_file" continue || return 2
  else
    write_unit_decision "$EVIDENCE/$decision_file" rollback || return 2
  fi
  require_unit_decision "$EVIDENCE/$decision_file" continue
}

run_unit1() {
  local suite_output suite_rc summary failed

  suite_output="$(bash tests/test-generate-paseo-config.sh 2>&1)"
  suite_rc=$?
  printf '%s\n' "$suite_output"
  [ "$suite_rc" -eq 0 ] || return "$suite_rc"

  suite_output="$(bash tests/test-no-private-identifiers.sh 2>&1)"
  suite_rc=$?
  printf '%s\n' "$suite_output"
  [ "$suite_rc" -eq 0 ] || return "$suite_rc"

  summary="$(printf '%s\n' "$suite_output" | grep '^SUMMARY ' | tail -1)"
  failed="$(printf '%s' "$summary" | cut -d' ' -f3)"
  [ -n "$summary" ] && [ "$failed" = "0" ]
}

request_shape_decision() {
  if [ -z "${DECISION_REQUEST_PATH:-}" ]; then
    printf 'DECISION_REQUEST_PATH is required when Paseo shape cannot be observed\n' >&2
    return 2
  fi
  write_decision_request "$DECISION_REQUEST_PATH" \
    'Paseo の on-disk shape を検証できない。spec v3 を改訂するか、観測できる Paseo config を用意するか' \
    'spec v3 を改訂する' \
    '観測できる Paseo config を用意する' || return 2
  return 2
}

observe_paseo_shape() {
  local paseo_config="${PASEO_CONFIG:-$HOME/.paseo/config.json}"
  if ! test -f "$paseo_config" || test -L "$paseo_config"; then
    request_shape_decision
    return $?
  fi
  if ! jq -e '
    def profile_shape:
      type == "object" and
      ((keys - ["featureValues","id","modeId","model","name","provider","thinkingOptionId"]) | length) == 0 and
      ((["id","model","name","provider","thinkingOptionId"] - keys) | length) == 0 and
      ([.id,.name,.provider,.model,.thinkingOptionId] | all(type == "string" and length > 0)) and
      ((has("modeId") | not) or (.modeId | type == "string" and length > 0)) and
      ((has("featureValues") | not) or (.featureValues | type == "object"));
    def base_record:
      type == "object" and has("env") and (.env | type == "object") and (has("extends") | not);
    def non_primary_record:
      type == "object" and has("extends") and (.extends | type == "string" and length > 0) and
      has("label") and (.label | type == "string") and has("env") and (.env | type == "object");
    . as $paseo |
    (.daemon | type == "object") and (.agents | type == "object") and
    (.daemon.agentProfiles | type == "array" and length > 0) and
    (.agents.providers | type == "object" and length > 0) and
    (all(.daemon.agentProfiles[]; profile_shape)) and
    (all(.agents.providers | to_entries[] | .value; type == "object")) and
    (any(.agents.providers | to_entries[] | .value; base_record)) and
    (any(.agents.providers | to_entries[] | .value; non_primary_record)) and
    ($paseo | type == "object")
  ' "$paseo_config" >/dev/null 2>&1; then
    request_shape_decision
    return $?
  fi
  local root_config="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
  if test -f "$root_config" && test ! -L "$root_config"; then
    if ! jq -e --slurpfile paseo "$paseo_config" '
      (.providers | keys | map(select(. != "claude" and . != "codex"))) as $families |
      all($families[]; . as $family | $paseo[0].agents.providers | has($family))
    ' "$root_config" >/dev/null 2>&1; then
      request_shape_decision
      return $?
    fi
  fi
  mkdir -p "$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets" || return 2
  ( umask 077
    printf '%s\n' '{"daemon":{"type":"object"},"daemonAgentProfiles":{"type":"array","nonEmpty":true},"profile":{"requiredKeys":["id","model","name","provider","thinkingOptionId"],"optionalKeys":["modeId","featureValues"],"optionalKeyTypes":{"modeId":"string","featureValues":"object"},"additionalProperties":false},"providers":{"type":"object","hasBaseRecord":true,"hasNonPrimaryRecord":true,"allowUnmanagedRecords":true,"base":{"env":"object","extendsAbsent":true},"nonPrimary":{"extends":"string","label":"string","env":"object"}}}' > "$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets/observed-shape.json.tmp"
  ) || return 2
  mv "$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets/observed-shape.json.tmp" \
    "$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets/observed-shape.json"
}

resolve_unit3_plan() {
  printf '%s\n' "${PASEO_PLAN_PATH:-}"
}

validate_unit3_plan() {
  local validator="$1" plan_file="$2"
  local fixture_plan="$CHEZMOI_SOURCE/tests/fixtures/agent-config/mad/plans/valid-plan.md"
  case "$plan_file" in
    /*) : ;;
    *) return 2 ;;
  esac
  test -f "$plan_file" || return 1
  if [ "$plan_file" = "$fixture_plan" ]; then
    test "${PASEO_UNIT3_PLAN_FIXTURE:-0}" = 1 || return 2
  elif test "${PASEO_UNIT3_PLAN_FIXTURE:-0}" = 1; then
    return 2
  fi
  node "$validator" "$plan_file"
}

write_unit3_failure() {
  local failure_path="$1" failure_text="$2"
  local failure_contents
  printf -v failure_contents '%s\n' "$failure_text"
  _write_unit_gate_private_file "$failure_path" "$failure_contents"
}

record_unit3() {
  local plan_file validate request_path failures="" status
  EVIDENCE="${PASEO_MIGRATION_EVIDENCE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/paseo-agent-config-migration/evidence}"
  plan_file="$(resolve_unit3_plan)"
  validate="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-plan-dependency-validate"
  request_path="${DECISION_REQUEST_PATH:-$EVIDENCE/clean-apply-decision-request.md}"

  check() {
    local name="$1"
    shift
    "$@" >/dev/null 2>&1
    status=$?
    test "$status" -eq 0 || failures="$failures$name(exit $status) "
  }

  check unit1-decision require_unit_decision "$EVIDENCE/unit1-decision.txt" continue
  check unit2-decision require_unit_decision "$EVIDENCE/unit2-decision.txt" continue
  check representative-decision require_unit_decision "$EVIDENCE/representative-decision.txt" approved-success
  check clean-apply-result require_unit_decision "$EVIDENCE/clean-apply-result.txt" approved-success
  check full-suite bash tests/run-tests.sh
  check absence bash tests/test-paseo-legacy-removal.sh
  check representative-verify bash tests/manual/mad-representative-run.sh \
    --verify-only --evidence-dir "$EVIDENCE/representative"
  check plan-dependency validate_unit3_plan "$validate" "$plan_file"

  if test -s "$request_path"; then
    failures="$failures"'decision-request(exit 1) '
  fi

  if test -s "$request_path"; then
    write_unit_decision "$EVIDENCE/unit3-decision.txt" decision_request || return 2
  elif test -z "$failures"; then
    write_unit_decision "$EVIDENCE/unit3-decision.txt" continue || return 2
  else
    write_unit_decision "$EVIDENCE/unit3-decision.txt" rollback || return 2
  fi

  if test -n "$failures"; then
    write_unit3_failure "$EVIDENCE/unit3-failure.txt" \
      "failed preconditions: $failures
rollback target: Task 8 through Task 11" || return 2
  else
    rm -f "$EVIDENCE/unit3-failure.txt" || return 2
  fi
  require_unit_decision "$EVIDENCE/unit3-decision.txt" continue
}

case "${1:-}" in
  record-unit1) record unit1-decision.txt run_unit1 ;;
  require)
    [ "$#" -eq 3 ] || exit 2
    require_unit_decision "$EVIDENCE/$2" "$3"
    ;;
  observe) observe_paseo_shape ;;
  record-unit2) record unit2-decision.txt bash -c 'bash tests/test-generate-paseo-config.sh \
    && bash tests/test-agent-env-script.sh \
    && bash tests/test-distribution.sh \
    && bash tests/test-no-private-identifiers.sh' ;;
  record-unit3) record_unit3 ;;
  *) printf 'usage: paseo-unit-gate.sh {record-unit1|observe|record-unit2|record-unit3|require <file> <value>}\n' >&2; exit 2 ;;
esac
