#!/usr/bin/env bash
# agent ラッパーが provider id から環境変数を決め、AI CLI を exec することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

AGENT="$CHEZMOI_SOURCE/private_dot_local/bin/executable_agent"
FIXTURE="$CHEZMOI_SOURCE/tests/fixtures/agent-launch/config.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
XDG="$TMP/xdg"
mkdir -p "$XDG" "$TMP/bin"

# 偽の AI CLI。受け取った環境変数と引数、自分の pid を 1 行で出す。
for name in claude codex opencode; do
  cat > "$TMP/bin/$name" <<'EOS'
#!/usr/bin/env bash
printf 'binary=%s pid=%s AGENT_ENV=%s CLAUDE_CONFIG_DIR=%s CODEX_HOME=%s args=%s\n' \
  "$(basename "$0")" "$$" "${AGENT_ENV-}" "${CLAUDE_CONFIG_DIR-}" "${CODEX_HOME-}" "$*"
EOS
  chmod +x "$TMP/bin/$name"
done

# 実行元の AI 環境を継承しないよう、3 つの変数を外してから起動する。
run_agent() {
  env -u AGENT_ENV -u CLAUDE_CONFIG_DIR -u CODEX_HOME \
    PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$XDG" AGENT_CONFIG="$FIXTURE" \
    bash "$AGENT" "$@" 2>&1
}

# --- 既定環境の provider id ---
out="$(run_agent --provider=claude)"
assert_contains "$out" "binary=claude " "既定環境: family と同じ名前のコマンドを起動する"
assert_contains "$out" "AGENT_ENV=primary " "既定環境: AGENT_ENV に既定環境名を設定する"
assert_contains "$out" "CLAUDE_CONFIG_DIR=$XDG/claude " "既定環境: サフィックスの無い設定ディレクトリを設定する"

# --- 既定環境でない provider id ---
out="$(run_agent --provider=claude-lab)"
assert_contains "$out" "AGENT_ENV=lab " "非既定環境: AGENT_ENV に環境名を設定する"
assert_contains "$out" "CLAUDE_CONFIG_DIR=$XDG/claude_lab " "非既定環境: サフィックス付きの設定ディレクトリを設定する"
out="$(run_agent --provider=codex-lab)"
assert_contains "$out" "binary=codex " "非既定環境: codex family を起動する"
assert_contains "$out" "CODEX_HOME=$XDG/codex_lab " "非既定環境: CODEX_HOME を設定する"
assert_contains "$out" "CLAUDE_CONFIG_DIR= " "非既定環境: 他の family の変数は設定しない"

# --- setup が null の family ---
out="$(run_agent --provider=opencode)"
assert_contains "$out" "AGENT_ENV=primary " "setup:null: AGENT_ENV は設定する"
assert_contains "$out" "CLAUDE_CONFIG_DIR= " "setup:null: 設定ディレクトリの変数を設定しない"
assert_contains "$out" "CODEX_HOME= " "setup:null: CODEX_HOME も設定しない"

# --- 引数の受け渡し ---
out="$(run_agent --provider claude -p 'hello world')"
assert_contains "$out" "args=-p hello world" "--provider <値> の形を受ける"
out="$(run_agent --provider=claude -- --provider=codex)"
assert_contains "$out" "args=--provider=codex" "-- 以降は family のコマンドへ渡す"
assert_contains "$out" "binary=claude " "-- 以降の --provider は解釈しない"

# --- 誤った呼び出し ---
out="$(run_agent --provider=nosuch)" && status=0 || status=$?
assert_eq "$status" "2" "正本に無い provider id は exit 2"
assert_contains "$out" "claude-lab" "正本に無い provider id は使える id の一覧を出す"
out="$(run_agent -p hello)" && status=0 || status=$?
assert_eq "$status" "2" "--provider を省くと exit 2"
assert_contains "$out" "claude-lab" "--provider を省くと使える id の一覧を出す"
out="$(run_agent --provider=claude --provider=codex)" && status=0 || status=$?
assert_eq "$status" "2" "--provider の重複は exit 2"
out="$(run_agent --provider=)" && status=0 || status=$?
assert_eq "$status" "2" "--provider の値が空なら exit 2"
out="$(env -u AGENT_ENV PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$XDG" \
  AGENT_CONFIG="$TMP/missing.json" bash "$AGENT" --provider=claude 2>&1)" && status=0 || status=$?
assert_eq "$status" "2" "正本を読めないと exit 2"

# --- exec で置き換わる ---
# 外側の bash が agent を exec し、agent が偽の claude を exec する。3 つが同じ
# pid になれば、ラッパーのプロセスは残っていない。
out="$(env -u AGENT_ENV PATH="$TMP/bin:$PATH" XDG_CONFIG_HOME="$XDG" AGENT_CONFIG="$FIXTURE" \
  bash -c 'printf "shell=%s\n" "$$"; exec bash "$1" --provider=claude' bash "$AGENT")"
shell_pid="$(printf '%s\n' "$out" | sed -n 's/^shell=//p')"
claude_pid="$(printf '%s\n' "$out" | sed -n 's/.* pid=\([0-9][0-9]*\) .*/\1/p')"
assert_eq "$claude_pid" "$shell_pid" "ラッパーは exec で置き換わり、自分のプロセスを残さない"
assert_contains "$(cat "$AGENT")" 'exec "$binary"' "ラッパーは exec で CLI を起動する"

# --- 配布する ---
managed="$(chezmoi managed --source "$CHEZMOI_SOURCE" 2>&1)"
assert_eq "$(printf '%s\n' "$managed" | grep -c '^\.local/bin/agent$')" "1" \
  "distribution: agent ラッパーを配る"
assert_contains "$managed" ".local/share/agent-config/launch-env.js" \
  "distribution: launch-env.js を配る"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
