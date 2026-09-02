#!/usr/bin/env bash
# mad-run が run ディレクトリと引数を用意し、レシピを呼ぶことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/recipes" "$FIXTURE/repo" "$FIXTURE/bin"
cp "$SRC/executable_mad-run" "$FIXTURE/scripts/mad-run"
cp "$SRC/mad-lib.sh" "$FIXTURE/scripts/mad-lib.sh"
chmod +x "$FIXTURE/scripts/mad-run"

cat > "$FIXTURE/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$FIXTURE/repo" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git"

# 環境と引数をそのまま出すだけのレシピ。
cat > "$FIXTURE/recipes/probe.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
printf 'run_dir=%s\n' "$MAD_RUN_DIR"
printf 'run_id=%s\n' "$MAD_RUN_ID"
printf 'timeout=%s\n' "$MAD_TIMEOUT"
printf 'dry=%s\n' "$MAD_DRY_RUN"
printf 'topic=%s\n' "$(mad_arg topic)"
printf 'missing=%s\n' "$(mad_arg nothere fallback)"
printf 'list=%s\n' "$(mad_arg_array items '["x"]')"
RECIPE

run() {
  MAD_RECIPES_DIR="$FIXTURE/recipes" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  bash "$FIXTURE/scripts/mad-run" "$@"
}

out="$(run probe --arg topic=abc --arg 'items=["a","b"]' --timeout 60 2>/dev/null)"
assert_contains "$out" "topic=abc" "文字列の引数を渡す"
assert_contains "$out" "missing=fallback" "無い引数は既定値になる"
assert_contains "$out" 'list=["a","b"]' "配列の引数を JSON 配列で渡す"
assert_contains "$out" "timeout=60" "タイムアウトを渡す"
assert_contains "$out" "dry=0" "既定は dry-run ではない"
assert_contains "$out" "run_dir=$FIXTURE/repo/_cellfusion/mad/" "run ディレクトリをリポジトリの下に作る"

out="$(run probe --arg topic=abc 2>/dev/null)"
assert_contains "$out" 'list=["x"]' "配列の引数が無ければ既定値になる"

run_dir="$(printf '%s\n' "$out" | sed -n 's/^run_dir=//p')"
assert_eq "$([ -f "$run_dir/args.json" ] && echo yes || echo no)" "yes" "args.json を書く"
assert_eq "$([ -d "$run_dir/.cache" ] && echo yes || echo no)" "yes" "キャッシュのディレクトリを作る"
assert_eq "$([ -f "$FIXTURE/repo/_cellfusion/.gitignore" ] && echo yes || echo no)" \
          "yes" "_cellfusion/.gitignore を用意する"

out="$(run probe --arg topic=abc --dry-run 2>/dev/null)"
assert_contains "$out" "dry=1" "--dry-run を渡す"

# 未知のレシピと引数の誤りは 2 で終わる。
run no-such-recipe >/dev/null 2>&1
assert_eq "$?" "2" "未知のレシピは 2 で終わる"
run probe --bogus >/dev/null 2>&1
assert_eq "$?" "2" "未知の引数は 2 で終わる"

# 値を取る引数に値が無いと 2 で終わる。直っていないと無限ループになるので、5 秒で殺す。
run_with_watchdog() {
  # 番人を殺したときのジョブの通知を出さないよう、subshell の標準エラーごと捨てる。
  (
    run "$@" >/dev/null 2>&1 &
    pid=$!
    ( sleep 5; kill -9 "$pid" 2>/dev/null ) &
    guard=$!
    wait "$pid"; rc=$?
    kill "$guard" 2>/dev/null
    exit "$rc"
  ) 2>/dev/null
}

run_with_watchdog probe --arg topic=abc --timeout
assert_eq "$?" "2" "値のない --timeout は 2 で終わる"
run_with_watchdog probe --arg
assert_eq "$?" "2" "値のない --arg は 2 で終わる"

# レシピの終了コードをそのまま返す。
printf 'exit 7\n' > "$FIXTURE/recipes/fail.sh"
run fail >/dev/null 2>&1
assert_eq "$?" "7" "レシピの終了コードを返す"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
