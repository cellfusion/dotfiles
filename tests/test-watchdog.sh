#!/usr/bin/env bash
# with_watchdog が、時間内に終わらないコマンドを子孫まで止めることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"
. "$(dirname "$0")/lib/watchdog.sh"

FIXTURE="$(mktemp -d)"
trap 'pkill -9 -f "$FIXTURE/hang.sh" 2>/dev/null; rm -rf "$FIXTURE"' EXIT

# 止めるまで終わらないスクリプト。watchdog が止める対象にする。
printf 'while :; do :; done\n' > "$FIXTURE/hang.sh"
printf 'exit 2\n' > "$FIXTURE/quick.sh"

# mad のテストと同じ形で、シェル関数から環境変数付きで起動する。
# 関数を挟むと $! が実際のコマンドの PID を指さないため、この形で検証する。
hang() { WATCHDOG_TEST=1 bash "$FIXTURE/hang.sh" "$@"; }
quick() { WATCHDOG_TEST=1 bash "$FIXTURE/quick.sh" "$@"; }

with_watchdog 2 quick --x
assert_eq "$?" "2" "時間内に終わるコマンドの終了コードをそのまま返す"

with_watchdog 2 hang --x
assert_eq "$?" "137" "時間内に終わらないコマンドは SIGKILL で終わる"

leftover="$(pgrep -f "$FIXTURE/hang.sh" | tr '\n' ' ')"
assert_eq "$leftover" "" "関数の下で起動したコマンドまで止める"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
