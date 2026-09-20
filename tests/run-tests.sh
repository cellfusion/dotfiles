#!/usr/bin/env bash
# Task 1–7 で管理するテストだけを明示順に実行する。
set -u

cd "$(dirname "$0")"

tests=(
  test-mad-task-brief.sh
  test-agent-config-policy.sh
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

total_failed=0
total_run=0

for t in "${tests[@]}"; do
  printf '%s\n' "$t"
  output=""
  status=0
  output="$(bash "$t" 2>&1)" || status=$?
  printf '%s\n' "$output" | grep -v '^SUMMARY ' || true
  summary="$(printf '%s\n' "$output" | grep '^SUMMARY ' | tail -1)"
  if [ -z "$summary" ]; then
    printf '  FAIL: %s が SUMMARY 行を出さなかった\n' "$t" >&2
    total_failed=$((total_failed + 1))
  else
    run="$(printf '%s' "$summary" | cut -d' ' -f2)"
    failed="$(printf '%s' "$summary" | cut -d' ' -f3)"
    total_run=$((total_run + run))
    total_failed=$((total_failed + failed))
    if [ "$status" -ne 0 ] && [ "$failed" -eq 0 ]; then
      total_failed=$((total_failed + 1))
    fi
  fi
done

printf 'SUMMARY %d %d\n' "$total_run" "$total_failed"
test "$total_failed" -eq 0
