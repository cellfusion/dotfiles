#!/usr/bin/env bash
# mad-run が run ディレクトリと引数を用意し、レシピを呼ぶことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/recipes" "$FIXTURE/repo/.git" "$FIXTURE/bin" \
         "$FIXTURE/bin-outside" "$FIXTURE/shared"
cp "$SRC/executable_mad-run" "$FIXTURE/scripts/mad-run"
cp "$SRC/mad-lib.sh" "$FIXTURE/scripts/mad-lib.sh"
chmod +x "$FIXTURE/scripts/mad-run"
cp "$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_agent-docs-dir" \
   "$FIXTURE/shared/agent-docs-dir"
chmod +x "$FIXTURE/shared/agent-docs-dir"

cat > "$FIXTURE/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-common-dir") printf '%s\n' "$FIXTURE/repo/.git" ;;
  "remote get-url origin") printf 'git@github.com:cellfusion/dotfiles.git\n' ;;
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

# ノードの出力が JSON でないときの mad_collect の返り値を見るレシピ。
cat > "$FIXTURE/recipes/collect.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
MAD_NODES="n1"
printf 'これは JSON ではない\n' > "$MAD_RUN_DIR/n1.json"
mad_collect >/dev/null || exit 5
exit 0
RECIPE

run() {
  MAD_RECIPES_DIR="$FIXTURE/recipes" \
  MAD_DOCS_DIR_BIN="$FIXTURE/shared/agent-docs-dir" \
  AGENT_DOCS_ROOT="$FIXTURE/docs" \
  PATH="$FIXTURE/bin:$PATH" \
  bash "$FIXTURE/scripts/mad-run" "$@"
}

out="$(run probe --arg topic=abc --arg 'items=["a","b"]' --timeout 60 2>/dev/null)"
assert_contains "$out" "topic=abc" "文字列の引数を渡す"
assert_contains "$out" "missing=fallback" "無い引数は既定値になる"
assert_contains "$out" 'list=["a","b"]' "配列の引数を JSON 配列で渡す"
assert_contains "$out" "timeout=60" "タイムアウトを渡す"
assert_contains "$out" "dry=0" "既定は dry-run ではない"
assert_contains "$out" "run_dir=$FIXTURE/docs/cellfusion/dotfiles/mad/" \
  "run ディレクトリを agent-docs-dir の下に作る"

out="$(run probe --arg topic=abc 2>/dev/null)"
assert_contains "$out" 'list=["x"]' "配列の引数が無ければ既定値になる"

run_dir="$(printf '%s\n' "$out" | sed -n 's/^run_dir=//p')"
assert_eq "$([ -f "$run_dir/args.json" ] && echo yes || echo no)" "yes" "args.json を書く"
assert_eq "$([ -d "$run_dir/.cache" ] && echo yes || echo no)" "yes" "キャッシュのディレクトリを作る"
assert_eq "${run_dir#"$FIXTURE/docs/"}" "cellfusion/dotfiles/mad/$(basename "$run_dir")" \
  "run ディレクトリが fixture の下にある"

src="$(cat "$FIXTURE/scripts/mad-run")"
assert_not_contains "$src" "MAD_GIT_BIN" "mad-run は git を差し替える環境変数を読まない"
assert_not_contains "$src" "rev-parse" "mad-run は git rev-parse を呼ばない"
assert_not_contains "$src" "_cellfusion" "mad-run は _cellfusion を書かない"

cat > "$FIXTURE/bin-outside/git" <<'OUTSIDE'
#!/usr/bin/env bash
exit 128
OUTSIDE
chmod +x "$FIXTURE/bin-outside/git"
MAD_RECIPES_DIR="$FIXTURE/recipes" \
MAD_DOCS_DIR_BIN="$FIXTURE/shared/agent-docs-dir" \
AGENT_DOCS_ROOT="$FIXTURE/docs-outside" \
PATH="$FIXTURE/bin-outside:$PATH" \
bash "$FIXTURE/scripts/mad-run" probe --arg topic=abc >/dev/null 2>&1
assert_eq "$?" "1" "git リポジトリの外では 1 で終わる"
assert_eq "$([ -d "$FIXTURE/docs-outside" ] && echo yes || echo no)" \
          "no" "git リポジトリの外では run ディレクトリを作らない"

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

# ノードの出力が JSON として読めないと mad_collect が非ゼロで返る。
run collect >/dev/null 2>&1
assert_eq "$?" "5" "出力が JSON でなければ mad_collect は非ゼロで返る"

# レシピの終了コードをそのまま返す。
printf 'exit 7\n' > "$FIXTURE/recipes/fail.sh"
run fail >/dev/null 2>&1
assert_eq "$?" "7" "レシピの終了コードを返す"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
