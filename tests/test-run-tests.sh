#!/usr/bin/env bash
# run-tests.sh が明示 allowlist の順序だけを実行することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
runner="$root/tests/run-tests.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fixture="$tmp/tests"
mkdir -p "$fixture"
cp "$runner" "$fixture/run-tests.sh"

expected_names=(
  test-mad-task-brief.sh
  test-single-implementer.sh
  test-paseo-cli-adapter.sh
  test-agent-config-policy.sh
  test-agent-config-routing.sh
  test-escalation-policy.sh
  test-paseo-plan-dependency-validate.sh
  test-manual-orchestration-contract.sh
  test-schemas.sh
  test-distribution.sh
  test-manual-scripts.sh
  test-tools-doc.sh
  test-instructions.sh
  test-paseo-legacy-removal.sh
  test-tests-not-distributed.sh
  test-mad-worktree.sh
  test-mad-progress.sh
  test-mad-worktrees-ledger.sh
  test-mad-worktree-contract-doc.sh
  test-mad-worktree-location-doc.sh
  test-run-tests.sh
)
expected_order="$(printf '%s\n' "${expected_names[@]}")"
order_file="$tmp/order"
export ORDER_FILE="$order_file"

for name in "${expected_names[@]}"; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    "printf '%s\\n' '$name' >> \"\$ORDER_FILE\"" \
    "printf 'SUMMARY 1 0\\n'" > "$fixture/$name"
  chmod +x "$fixture/$name"
done

sentinel="$fixture/test-untouched.sh"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  "printf '%s\\n' sentinel >> \"\$ORDER_FILE\"" \
  "printf 'SUMMARY 1 0\\n'" > "$sentinel"
chmod +x "$sentinel"

output=""
status=0
output="$(bash "$fixture/run-tests.sh" 2>&1)" || status=$?
assert_eq "$status" 0 'runner: 選択された stub suite が成功する'
assert_eq "$(cat "$order_file")" "$expected_order" \
  'runner: allowlist の順序をそのまま実行する'
assert_not_contains "$(cat "$order_file")" sentinel \
  'runner: allowlist 外の sentinel を実行しない'
assert_contains "$output" 'SUMMARY 21 0' \
  'runner: 最終 SUMMARY に実行数と失敗数を出す'

assert_summary
