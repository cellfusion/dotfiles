#!/usr/bin/env bash
# mad-runs が run を一覧し、詳細を出し、古いものだけを片付けることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/bin" "$FIXTURE/runs"
cp "$SRC/executable_mad-runs" "$FIXTURE/mad-runs"
chmod +x "$FIXTURE/mad-runs"

# archive の呼び出しを記録するだけの偽の paseo。
cat > "$FIXTURE/bin/paseo" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$FIXTURE/archived.txt"
printf '{"status":"archived"}\n'
FAKE
chmod +x "$FIXTURE/bin/paseo"

mk_run() {
  local id="$1" recipe="$2" status="$3" age_days="$4"
  local d="$FIXTURE/runs/$id"
  mkdir -p "$d"
  printf '{"recipe":"%s","args":{},"cwd":"/tmp","base":"main","startedAt":"2026-09-01T00:00:00Z","timeout":1200,"maxParallel":4}\n' \
    "$recipe" > "$d/run.json"
  if [ -n "$status" ]; then
    printf '{"status":"%s","finishedAt":"2026-09-01T00:01:00Z","exitCode":0}\n' \
      "$status" > "$d/result.json"
  fi
  printf 'state=ok\nrole=researcher\nworkspace=\nstartedAt=x\nfinishedAt=y\n' > "$d/n1.state"
  printf 'wks_%s\t/tmp/wt-%s\tmad/%s\n' "$id" "$id" "$id" > "$d/workspaces.txt"
  # 更新時刻を指定の日数だけ過去にする。BSD と GNU の touch で書式が違う。
  touch -t "$(date -v-"${age_days}"d +%Y%m%d0000)" "$d" 2>/dev/null ||
    touch -d "${age_days} days ago" "$d"
}

mk_run old-run research ok 30
mk_run new-run implement "" 0

runs() {
  MAD_RUNS_DIR="$FIXTURE/runs" MAD_PASEO_BIN="$FIXTURE/bin/paseo" \
  bash "$FIXTURE/mad-runs" "$@"
}

# ls
out="$(runs ls 2>&1)"
assert_contains "$out" "old-run" "ls: run の id を出す"
assert_contains "$out" "research" "ls: レシピ名を出す"
assert_contains "$out" "new-run" "ls: 終わっていない run も出す"
assert_contains "$out" "running" "ls: result.json が無い run は running と出す"

# show
out="$(runs show old-run 2>&1)"
assert_contains "$out" "recipe: research" "show: レシピ名を出す"
assert_contains "$out" "n1" "show: ノード名を出す"
assert_contains "$out" "state=ok" "show: ノードの状態を出す"
assert_contains "$out" "wks_old-run" "show: 作った workspace を出す"

runs show nosuch >/dev/null 2>&1
assert_eq "$?" "2" "show: 無い run は 2 で終わる"
runs show >/dev/null 2>&1
assert_eq "$?" "2" "show: run id が無いと 2 で終わる"

# clean（--yes なし）
out="$(runs clean --older-than 7 2>&1)"
assert_contains "$out" "old-run" "clean: 古い run を対象に挙げる"
assert_not_contains "$out" "new-run" "clean: 新しい run は対象にしない"
assert_eq "$([ -d "$FIXTURE/runs/old-run" ] && echo yes || echo no)" "yes" \
  "clean: --yes なしでは消さない"
assert_eq "$([ -f "$FIXTURE/archived.txt" ] && echo yes || echo no)" "no" \
  "clean: --yes なしでは archive しない"

# clean（--yes あり）
runs clean --older-than 7 --yes >/dev/null 2>&1
assert_eq "$([ -d "$FIXTURE/runs/old-run" ] && echo yes || echo no)" "no" \
  "clean: --yes で古い run を消す"
assert_eq "$([ -d "$FIXTURE/runs/new-run" ] && echo yes || echo no)" "yes" \
  "clean: --yes でも新しい run は残す"
assert_contains "$(cat "$FIXTURE/archived.txt")" "workspace archive wks_old-run" \
  "clean: --yes で workspace を archive する"

# 未知のサブコマンドと引数
runs bogus >/dev/null 2>&1
assert_eq "$?" "2" "未知のサブコマンドは 2 で終わる"
runs clean --older-than >/dev/null 2>&1
assert_eq "$?" "2" "値のない --older-than は 2 で終わる"
runs >/dev/null 2>&1
assert_eq "$?" "2" "サブコマンドが無いと 2 で終わる"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
