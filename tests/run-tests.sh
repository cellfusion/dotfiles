#!/usr/bin/env bash
# tests/test-*.sh を全部実行し、1 つでも失敗したら非ゼロで終了する。
set -u

cd "$(dirname "$0")"

total_failed=0
total_run=0

for t in test-*.sh; do
  [ -e "$t" ] || continue
  printf '%s\n' "$t"
  # 各テストは失敗数と実行数を最終行に "SUMMARY <run> <failed>" で出す。
  output="$(bash "$t" 2>&1)"
  printf '%s\n' "$output" | grep -v '^SUMMARY '
  summary="$(printf '%s\n' "$output" | grep '^SUMMARY ' | tail -1)"
  if [ -z "$summary" ]; then
    printf '  FAIL: %s が SUMMARY 行を出さなかった\n' "$t" >&2
    total_failed=$((total_failed + 1))
    continue
  fi
  run="$(printf '%s' "$summary" | cut -d' ' -f2)"
  failed="$(printf '%s' "$summary" | cut -d' ' -f3)"
  total_run=$((total_run + run))
  total_failed=$((total_failed + failed))
done

printf '\n%d 件中 %d 件失敗\n' "$total_run" "$total_failed"
[ "$total_failed" -eq 0 ]
