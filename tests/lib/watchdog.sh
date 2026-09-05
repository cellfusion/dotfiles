#!/usr/bin/env bash
# 止まらないかもしれないコマンドを制限時間つきで実行する。テストから source して使う。
#
# with_watchdog <秒> <コマンド> [引数...]
#
# コマンドが時間内に終われば、その終了コードをそのまま返す。
# 終わらなければプロセスグループごと SIGKILL で止め、137 を返す。
# シェル関数を渡すと $! はその関数を実行するサブシェルを指し、
# 関数が起動した外部コマンドは別 PID になる。PID を 1 つ止めるだけでは
# 外部コマンドが孤児として残るため、set -m でジョブを独立した
# プロセスグループにしてグループごと止める。
with_watchdog() {
  watchdog_limit=$1; shift
  (
    set -m
    "$@" >/dev/null 2>&1 &
    pid=$!
    ( sleep "$watchdog_limit"; kill -9 -"$pid" 2>/dev/null ) &
    guard=$!
    wait "$pid"; rc=$?
    kill -TERM -"$guard" 2>/dev/null
    exit "$rc"
  ) 2>/dev/null
}
