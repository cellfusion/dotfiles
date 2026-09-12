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
  local suite
  if "$@"; then
    suite=0
  else
    suite=$?
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

case "${1:-}" in
  record-unit1) record unit1-decision.txt run_unit1 ;;
  require)
    [ "$#" -eq 3 ] || exit 2
    require_unit_decision "$EVIDENCE/$2" "$3"
    ;;
  observe) observe_paseo_shape ;;
  record-unit2|record-unit3) printf '%s is not implemented yet\n' "${1:-}" >&2; exit 2 ;;
  *) printf 'usage: paseo-unit-gate.sh {record-unit1|observe|record-unit2|record-unit3|require <file> <value>}\n' >&2; exit 2 ;;
esac
