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
  "branch --show-current") printf '%s\n' "\${FAKE_BRANCH-main}" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git"

cat > "$FIXTURE/bin/paseo-ws" <<'FAKE'
#!/usr/bin/env bash
[ "$1 $2" = "workspace create" ] || exit 1
printf '{"workspaceId":"wks_fake","project":"p","name":"n","isolation":"worktree","cwd":"/tmp/fake-wt"}\n'
FAKE
chmod +x "$FIXTURE/bin/paseo-ws"

in_repo() {
  ( cd "$FIXTURE/repo" && MAD_RECIPES_DIR="$FIXTURE/recipes" \
    MAD_GIT_BIN="$FIXTURE/bin/git" MAD_PASEO_BIN="$FIXTURE/bin/paseo-ws" \
    bash "$FIXTURE/scripts/mad-run" "$@" )
}

# 環境と引数をそのまま出すだけのレシピ。
cat > "$FIXTURE/recipes/probe.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' 'topic items nothere'
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

# 引数を宣言するレシピ。宣言の検証と spec モードの出力を見る。
cat > "$FIXTURE/recipes/declared.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare 'topic' 'perspectives depth'
printf 'topic=%s\n' "$(mad_arg topic)"
RECIPE

run() {
  MAD_RECIPES_DIR="$FIXTURE/recipes" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  bash "$FIXTURE/scripts/mad-run" "$@"
}

# mad-run は標準エラーに run の id を出す。同じ秒に作られた run と取り違えないよう、
# ディレクトリの新しさではなく id で引く。
run_dir_from() {
  printf '%s' "$FIXTURE/repo/_cellfusion/mad/$(grep -o \
    '[0-9]\{8\}T[0-9]\{6\}-[0-9a-f]\{6\}' "$1" | head -1)"
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

# ノードの出力が JSON として読めないと mad_collect が非ゼロで返る。
run collect >/dev/null 2>&1
assert_eq "$?" "5" "出力が JSON でなければ mad_collect は非ゼロで返る"

# レシピの終了コードをそのまま返す。
printf 'exit 7\n' > "$FIXTURE/recipes/fail.sh"
run fail >/dev/null 2>&1
assert_eq "$?" "7" "レシピの終了コードを返す"

# --- 引数の宣言 ---
out="$(run declared --arg topic=abc 2>/dev/null)"
assert_contains "$out" "topic=abc" "宣言した引数は通る"

run declared --arg topic=abc --arg 'perspective=x' >/dev/null 2>&1
assert_eq "$?" "2" "宣言に無い引数は 2 で終わる"

err="$(run declared --arg topic=abc --arg 'perspective=x' 2>&1 >/dev/null)"
assert_contains "$err" "perspective" "宣言に無い引数の名前を出す"

run declared >/dev/null 2>&1
assert_eq "$?" "2" "必須の引数が無いと 2 で終わる"

out="$(MAD_SPEC_ONLY=1 MAD_RUN_DIR=/dev/null MAD_SCRIPTS="$FIXTURE/scripts" \
  bash "$FIXTURE/recipes/declared.sh" 2>/dev/null)"
assert_contains "$out" "required=topic" "spec モードで必須の引数を出す"
assert_contains "$out" "optional=perspectives depth" "spec モードで省略可の引数を出す"

# --- レシピ一覧 ---
out="$(run 2>&1)"
assert_contains "$out" "declared" "引数なしで呼ぶとレシピ名を出す"
assert_contains "$out" "必須: topic" "引数なしで呼ぶと必須の引数を出す"
assert_contains "$out" "省略可: perspectives depth" "引数なしで呼ぶと省略可の引数を出す"

# --- run のメタ情報 ---
out="$(run probe --arg topic=abc --timeout 60 --max-parallel 2 2>/dev/null)"
run_dir="$(printf '%s\n' "$out" | sed -n 's/^run_dir=//p')"
assert_eq "$(jq -r '.recipe' "$run_dir/run.json")" "probe" "run.json にレシピ名を書く"
assert_eq "$(jq -r '.args.topic' "$run_dir/run.json")" "abc" "run.json に引数を書く"
assert_eq "$(jq -r '.timeout' "$run_dir/run.json")" "60" "run.json にタイムアウトを書く"
assert_eq "$(jq -r '.maxParallel' "$run_dir/run.json")" "2" "run.json に同時実行数の上限を書く"
assert_eq "$(jq -r '.base' "$run_dir/run.json")" "" "run.json の base は空で始まる"
assert_eq "$(jq -r '.status' "$run_dir/result.json")" "ok" "成功したら result.json は ok"

out="$(run probe --arg topic=abc 2>/dev/null)"
run_dir="$(printf '%s\n' "$out" | sed -n 's/^run_dir=//p')"
assert_eq "$(jq -r '.maxParallel' "$run_dir/run.json")" "4" "同時実行数の上限は既定 4"

printf 'exit 3\n' > "$FIXTURE/recipes/broken.sh"
run broken >/dev/null 2>"$FIXTURE/broken.err"
run_dir="$(run_dir_from "$FIXTURE/broken.err")"
assert_eq "$(jq -r '.status' "$run_dir/result.json")" "failed" "失敗したら result.json は failed"
assert_eq "$(jq -r '.exitCode' "$run_dir/result.json")" "3" "result.json に終了コードを書く"

# --- 切り離し実行 ---
cat > "$FIXTURE/recipes/slow.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' ''
sleep 2
printf 'done\n' > "$MAD_RUN_DIR/slow.txt"
RECIPE

id="$(run slow --detach 2>/dev/null | tail -1)"
assert_contains "$id" "T" "--detach は run id を返す"
assert_eq "$([ -f "$FIXTURE/repo/_cellfusion/mad/$id/slow.txt" ] && echo yes || echo no)" \
          "no" "--detach は待たずに返る"
i=0
while [ "$i" -lt 30 ] && [ ! -f "$FIXTURE/repo/_cellfusion/mad/$id/result.json" ]; do
  sleep 1; i=$((i + 1))
done
assert_eq "$([ -f "$FIXTURE/repo/_cellfusion/mad/$id/slow.txt" ] && echo yes || echo no)" \
          "yes" "--detach したレシピは背景で走り切る"
assert_eq "$(jq -r '.status' "$FIXTURE/repo/_cellfusion/mad/$id/result.json")" \
          "ok" "--detach でも result.json を書く"

run slow --detach --dry-run >/dev/null 2>&1
assert_eq "$?" "2" "--detach と --dry-run は同時に渡せない"

# --- 同時実行数の上限 ---
# 偽の mad-agent が開始と終了を 1 つのファイルに追記する。上限 1 なら重ならない。
cat > "$FIXTURE/scripts/mad-agent" <<'FAKE'
#!/usr/bin/env bash
out=""; title=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) out="$2"; shift 2 ;;
    --title) title="$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'start %s\n' "${title##*/}" >> "$MAD_RUN_DIR/order.txt"
sleep 1
printf 'end %s\n' "${title##*/}" >> "$MAD_RUN_DIR/order.txt"
printf '{"summary":"ok"}\n' > "$out"
FAKE
chmod +x "$FIXTURE/scripts/mad-agent"

cat > "$FIXTURE/recipes/par.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' ''
i=1
while [ "$i" -le 3 ]; do
  printf 'x\n' | mad_prompt "p$i"
  mad_start_node "p$i" researcher
  i=$((i + 1))
done
mad_join || exit 1
RECIPE

run par --max-parallel 1 >/dev/null 2>"$FIXTURE/par.err"
run_dir="$(run_dir_from "$FIXTURE/par.err")"
assert_eq "$(grep -c '^start ' "$run_dir/order.txt")" "3" "上限 1: 3 ノードすべて走る"
assert_eq "$(awk '/^start /{if(o){b=1} o=1} /^end /{o=0} END{print b+0}' \
  "$run_dir/order.txt")" "0" "上限 1: ノードが重ならない"

run par --max-parallel 3 >/dev/null 2>"$FIXTURE/par3.err"
run_dir="$(run_dir_from "$FIXTURE/par3.err")"
assert_eq "$(awk '/^start /{if(o){b=1} o=1} /^end /{o=0} END{print b+0}' \
  "$run_dir/order.txt")" "1" "上限 3: ノードが重なる"

# --- mad_text ---
# 呼び出し元の cwd を基準にするので、レシピは repo の中から呼ぶ。
cat > "$FIXTURE/recipes/text.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' 'src'
t="$(mad_text src)" || exit 1
printf 'text=[%s]\n' "$t"
RECIPE

printf '要件の本文\n' > "$FIXTURE/repo/req.md"
out="$(in_repo text --arg src=req.md 2>/dev/null)"
assert_contains "$out" "text=[要件の本文" "mad_text はファイルの中身を読む"

out="$(in_repo text --arg 'src=そのままの文字列' 2>/dev/null)"
assert_contains "$out" "text=[そのままの文字列]" "mad_text は文字列をそのまま返す"

printf 'x\n' > "$FIXTURE/outside.md"
in_repo text --arg 'src=../outside.md' >/dev/null 2>&1
assert_eq "$?" "1" "mad_text は cwd の外のファイルで 1 を返す"

# --- mad_default_timeout ---
cat > "$FIXTURE/recipes/to.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' ''
mad_default_timeout 3600
printf 'timeout=%s\n' "$MAD_TIMEOUT"
RECIPE

out="$(run to 2>/dev/null)"
assert_contains "$out" "timeout=3600" "mad_default_timeout は既定を上書きする"
out="$(run to --timeout 90 2>/dev/null)"
assert_contains "$out" "timeout=90" "明示した --timeout は上書きされない"

# --- mad_worktree ---
cat > "$FIXTURE/recipes/wt.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' ''
ws="$(mad_worktree 'mad/test' main)" || exit 1
printf 'line=%s\n' "$ws"
RECIPE

wt() {
  MAD_RECIPES_DIR="$FIXTURE/recipes" MAD_GIT_BIN="$FIXTURE/bin/git" \
  MAD_PASEO_BIN="$FIXTURE/bin/paseo-ws" \
  bash "$FIXTURE/scripts/mad-run" wt "$@"
}

out="$(wt 2>"$FIXTURE/wt.err")"
assert_contains "$out" "line=workspace=wks_fake cwd=/tmp/fake-wt" \
  "mad_worktree は id と cwd を 1 行で返す"
run_dir="$(run_dir_from "$FIXTURE/wt.err")"
assert_contains "$(cat "$run_dir/workspaces.txt")" "wks_fake" \
  "mad_worktree は作った workspace を記録する"

out="$(wt --dry-run 2>/dev/null)"
assert_contains "$out" "workspace=dry-run" "mad_worktree は dry-run で workspace を作らない"

# --- mad_diff ---
cat > "$FIXTURE/bin/git-diff" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$FAKE_REPO" ;;
  *diff*) i=1; while [ "$i" -le 20 ]; do printf '+行 %s\n' "$i"; i=$((i + 1)); done ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git-diff"

cat > "$FIXTURE/recipes/df.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' ''
mad_diff /tmp/fake-wt main 5
RECIPE

out="$(FAKE_REPO="$FIXTURE/repo" MAD_RECIPES_DIR="$FIXTURE/recipes" \
  MAD_GIT_BIN="$FIXTURE/bin/git-diff" \
  bash "$FIXTURE/scripts/mad-run" df 2>/dev/null)"
assert_contains "$out" "+行 5" "mad_diff は差分を出す"
assert_not_contains "$out" "+行 6" "mad_diff は上限で切り詰める"
assert_contains "$out" "20 行" "mad_diff は全体の行数を添える"

# --- mad_base / mad_ws_field ---
cat > "$FIXTURE/recipes/base.sh" <<'RECIPE'
set -u
. "$MAD_SCRIPTS/mad-lib.sh"
mad_declare '' 'base'
b="$(mad_base)" || exit 2
printf 'base=%s\n' "$b"
printf 'id=%s\n' "$(mad_ws_field 'workspace=wks_1 cwd=/tmp/a b' id)"
printf 'cwd=%s\n' "$(mad_ws_field 'workspace=wks_1 cwd=/tmp/a b' cwd)"
RECIPE

out="$(run base 2>/dev/null)"
assert_contains "$out" "base=main" "mad_base は現在のブランチを使う"
assert_contains "$out" "id=wks_1" "mad_ws_field は workspace の id を取り出す"
assert_contains "$out" "cwd=/tmp/a b" "mad_ws_field は空白を含む cwd も取り出す"

out="$(run base --arg base=develop 2>/dev/null)"
assert_contains "$out" "base=develop" "mad_base は引数の base を優先する"

( export FAKE_BRANCH=""
  run base >/dev/null 2>&1 )
assert_eq "$?" "2" "mad_base は base が決まらないと非ゼロで返る"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
