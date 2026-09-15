#!/usr/bin/env bash
# unit-gate の evidence writer が symlink を追わず、0600 の atomic な regular file を残すことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"
. "$CHEZMOI_SOURCE/tests/lib/unit-gate.sh"

TMP="$(mktemp -d)"
OBSERVED_TARGET="$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets/observed-shape.json"
OBSERVED_BACKUP="$TMP/observed-shape.json.backup"
OBSERVED_TMP_LINK="$OBSERVED_TARGET.tmp"
restore_observed_fixture() {
  rm -f "$OBSERVED_TMP_LINK"
  if [ -e "$OBSERVED_BACKUP" ]; then
    rm -f "$OBSERVED_TARGET"
    mv "$OBSERVED_BACKUP" "$OBSERVED_TARGET"
  fi
  rm -rf "$TMP"
}
trap restore_observed_fixture EXIT
umask 077

assert_private_regular_file() {
  assert_eq "$(stat -f '%HT:%Lp' "$1" 2>/dev/null)" "Regular File:600" "$2"
}

DECISION_VICTIM="$TMP/decision-victim.txt"
DECISION_TARGET="$TMP/decision.txt"
printf 'keep-decision-victim\n' > "$DECISION_VICTIM"
ln -s "$DECISION_VICTIM" "$DECISION_TARGET"
write_unit_decision "$DECISION_TARGET" continue
assert_eq "$(cat "$DECISION_VICTIM")" "keep-decision-victim" \
  "decision: target symlink の参照先を変更しない"
assert_eq "$(cat "$DECISION_TARGET")" "continue" "decision: target symlink を regular file で置換する"
assert_private_regular_file "$DECISION_TARGET" "decision: target は 0600 regular file"

DECISION_TMP_VICTIM="$TMP/decision-tmp-victim.txt"
DECISION_TMP_TARGET="$TMP/decision-tmp.txt"
printf 'keep-decision-tmp-victim\n' > "$DECISION_TMP_VICTIM"
ln -s "$DECISION_TMP_VICTIM" "$DECISION_TMP_TARGET.tmp"
write_unit_decision "$DECISION_TMP_TARGET" rollback
assert_eq "$(cat "$DECISION_TMP_VICTIM")" "keep-decision-tmp-victim" \
  "decision: tmp symlink の参照先を変更しない"
assert_eq "$(cat "$DECISION_TMP_TARGET")" "rollback" "decision: tmp symlink があっても decision を書く"
assert_private_regular_file "$DECISION_TMP_TARGET" "decision: tmp symlink 後も 0600 regular file"

REQUEST_VICTIM="$TMP/request-victim.txt"
REQUEST_TARGET="$TMP/request.md"
printf 'keep-request-victim\n' > "$REQUEST_VICTIM"
ln -s "$REQUEST_VICTIM" "$REQUEST_TARGET"
write_decision_request "$REQUEST_TARGET" 'continue?' 'continue' 'rollback'
assert_eq "$(cat "$REQUEST_VICTIM")" "keep-request-victim" \
  "request: target symlink の参照先を変更しない"
assert_contains "$(cat "$REQUEST_TARGET")" '## Question' "request: question を書く"
assert_private_regular_file "$REQUEST_TARGET" "request: target は 0600 regular file"

REQUEST_TMP_VICTIM="$TMP/request-tmp-victim.txt"
REQUEST_TMP_TARGET="$TMP/request-tmp.md"
printf 'keep-request-tmp-victim\n' > "$REQUEST_TMP_VICTIM"
ln -s "$REQUEST_TMP_VICTIM" "$REQUEST_TMP_TARGET.tmp"
write_decision_request "$REQUEST_TMP_TARGET" 'retry?' 'retry' 'stop'
assert_eq "$(cat "$REQUEST_TMP_VICTIM")" "keep-request-tmp-victim" \
  "request: tmp symlink の参照先を変更しない"
assert_contains "$(cat "$REQUEST_TMP_TARGET")" '- retry' "request: tmp symlink があっても options を書く"
assert_private_regular_file "$REQUEST_TMP_TARGET" "request: tmp symlink 後も 0600 regular file"

EXISTING_TARGET="$TMP/existing.txt"
printf 'old decision\n' > "$EXISTING_TARGET"
chmod 644 "$EXISTING_TARGET"
write_unit_decision "$EXISTING_TARGET" approved-success
assert_eq "$(cat "$EXISTING_TARGET")" "approved-success" "decision: existing target を完全に置換する"
assert_private_regular_file "$EXISTING_TARGET" "decision: existing target は 0600 regular file"

FAKE_BIN="$TMP/fake-bin"
mkdir "$FAKE_BIN"
cat > "$FAKE_BIN/chmod" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 700 "$FAKE_BIN/chmod"
PARTIAL_TARGET="$TMP/partial.txt"
printf 'old value\n' > "$PARTIAL_TARGET"
chmod 600 "$PARTIAL_TARGET"
ORIGINAL_PATH="$PATH"
PATH="$FAKE_BIN:$PATH"
hash -r
write_unit_decision "$PARTIAL_TARGET" continue
partial_status=$?
PATH="$ORIGINAL_PATH"
hash -r
assert_eq "$partial_status" "2" "decision: temp の permission 設定失敗を返す"
assert_eq "$(cat "$PARTIAL_TARGET")" "old value" "decision: partial failure で existing target を残す"
assert_eq "$(find "$TMP" -maxdepth 1 \( -name '.partial.txt.tmp.*' -o -name 'partial.txt.tmp' \) -print)" "" \
  "decision: partial failure で temp を残さない"

CONCURRENT_TARGET="$TMP/concurrent.txt"
(
  write_unit_decision "$CONCURRENT_TARGET" continue
  printf '%s' "$?" > "$TMP/concurrent-one-status"
) &
concurrent_one=$!
(
  write_unit_decision "$CONCURRENT_TARGET" rollback
  printf '%s' "$?" > "$TMP/concurrent-two-status"
) &
concurrent_two=$!
wait "$concurrent_one"
wait "$concurrent_two"
assert_eq "$(cat "$TMP/concurrent-one-status")" "0" "decision: concurrent writer one が成功する"
assert_eq "$(cat "$TMP/concurrent-two-status")" "0" "decision: concurrent writer two が成功する"
case "$(cat "$CONCURRENT_TARGET")" in
  continue|rollback) concurrent_value=yes ;;
  *) concurrent_value=no ;;
esac
assert_eq "$concurrent_value" "yes" "decision: concurrent target は完全な decision だけを持つ"
assert_private_regular_file "$CONCURRENT_TARGET" "decision: concurrent target は 0600 regular file"

OBSERVED_CONFIG="$TMP/observed-paseo-config.json"
printf '%s\n' '{"daemon":{"agentProfiles":[{"id":"profile","name":"profile","provider":"base","model":"model","thinkingOptionId":"high"}]},"agents":{"providers":{"base":{"env":{}},"derived":{"extends":"base","label":"Derived","env":{}}}}}' > "$OBSERVED_CONFIG"
OBSERVED_VICTIM="$TMP/observed-shape-victim.json"
OBSERVED_TMP_VICTIM="$TMP/observed-shape-tmp-victim.json"
printf 'keep-observed-victim\n' > "$OBSERVED_VICTIM"
printf 'keep-observed-tmp-victim\n' > "$OBSERVED_TMP_VICTIM"
mv "$OBSERVED_TARGET" "$OBSERVED_BACKUP"
ln -s "$OBSERVED_VICTIM" "$OBSERVED_TARGET"
ln -s "$OBSERVED_TMP_VICTIM" "$OBSERVED_TMP_LINK"
PASEO_CONFIG="$OBSERVED_CONFIG" AGENT_CONFIG="$TMP/missing-agent-config.json" HOME="$TMP/home" \
  bash "$CHEZMOI_SOURCE/tests/manual/paseo-unit-gate.sh" observe \
  > "$TMP/observe.stdout" 2> "$TMP/observe.stderr"
observe_status=$?
assert_eq "$observe_status" "0" "observe: valid Paseo shape を記録する"
assert_eq "$(cat "$OBSERVED_VICTIM")" "keep-observed-victim" \
  "observe: target symlink の参照先を変更しない"
assert_eq "$(cat "$OBSERVED_TMP_VICTIM")" "keep-observed-tmp-victim" \
  "observe: fixed tmp symlink の参照先を変更しない"
assert_private_regular_file "$OBSERVED_TARGET" "observe: observed shape は 0600 regular file"
assert_eq "$(cat "$TMP/observe.stdout")" "" "observe: observed shape を stdout に出さない"
jq -e '.daemon.type == "object" and .profile.requiredKeys == ["id","model","name","provider","thinkingOptionId"]' \
  "$OBSERVED_TARGET" >/dev/null
assert_eq "$?" "0" "observe: 匿名 shape fixture を記録する"

printf 'old observed fixture\n' > "$OBSERVED_TARGET"
chmod 600 "$OBSERVED_TARGET"
OBSERVE_FAKE_BIN="$TMP/observe-fake-bin"
mkdir "$OBSERVE_FAKE_BIN"
cat > "$OBSERVE_FAKE_BIN/chmod" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod 700 "$OBSERVE_FAKE_BIN/chmod"
ORIGINAL_PATH="$PATH"
PATH="$OBSERVE_FAKE_BIN:$PATH"
hash -r
PASEO_CONFIG="$OBSERVED_CONFIG" AGENT_CONFIG="$TMP/missing-agent-config.json" HOME="$TMP/home" \
  bash "$CHEZMOI_SOURCE/tests/manual/paseo-unit-gate.sh" observe \
  > "$TMP/observe-failure.stdout" 2> "$TMP/observe-failure.stderr"
observe_failure_status=$?
PATH="$ORIGINAL_PATH"
hash -r
assert_eq "$observe_failure_status" "2" "observe: atomic write failure を返す"
assert_eq "$(cat "$OBSERVED_TARGET")" "old observed fixture" \
  "observe: atomic write failure で existing fixture を残す"
assert_eq "$(find "$(dirname "$OBSERVED_TARGET")" -maxdepth 1 -name '.observed-shape.json.tmp.*' -print)" "" \
  "observe: atomic write failure で temp を残さない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
