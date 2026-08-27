#!/usr/bin/env bash
# launch-claude-tab.sh が、claude を持たない環境でタブを作らないことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

# 環境定義は clone した人のマシンによって違うので、fixture を与えて描画する。
cfg="$(mktemp)"
cat > "$cfg" <<'EOF'
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "solo"
    label   = "P2"
    agents  = ["codex"]
EOF

SCRIPT="$(mktemp)"
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/herdr/executable_launch-claude-tab.sh.tmpl" > "$SCRIPT"
stub_dir="$(mktemp -d)"
trap 'rm -rf "$stub_dir" "$SCRIPT" "$cfg"' EXIT

# herdr を差し替える。呼ばれたら記録し、tab create には pane_id を返す。
cat > "$stub_dir/herdr" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$STUB_LOG"
if [ "$1" = tab ]; then printf '{"result":{"root_pane":{"pane_id":"p1"}}}\n'; fi
EOF
chmod +x "$stub_dir/herdr"

# $1 = HERDR_SESSION の値（"-" なら未設定）。$2 = AGENT_ENV_AGENTS の値（省略可）。
# 終了ステータス / herdr の呼び出し回数 / 出力を 3 ブロックで出す。
run_launcher() {
  local log status out session_env
  log="$(mktemp)"
  if [ "$1" = "-" ]; then session_env=(env -u HERDR_SESSION); else session_env=(env "HERDR_SESSION=$1"); fi
  out="$("${session_env[@]}" "AGENT_ENV_AGENTS=${2-}" "STUB_LOG=$log" \
    "PATH=$stub_dir:$PATH" bash "$SCRIPT" 2>&1)"
  status=$?
  printf '%s\n---\n%s\n---\n%s\n' "$status" "$(wc -l < "$log" | tr -d ' ')" "$out"
  rm -f "$log"
}

# --- claude を持たない環境では起動しない ---
result="$(run_launcher solo)"
assert_eq "$(printf '%s' "$result" | sed -n '1p')" "1" \
  "claude を持たない環境では非ゼロで終わる"
assert_eq "$(printf '%s' "$result" | sed -n '3p')" "0" \
  "claude を持たない環境では herdr を呼ばない"
assert_contains "$result" "not configured" \
  "claude を持たない環境では警告を出す"

# type="shell" のキーコマンドは herdr サーバが detached で起動するので、環境は
# focus 中の pane ではなくサーバのものを継承する。サーバの AGENT_ENV_* は
# サーバを起動したシェル（＝先頭環境）の値なので、判定には使えない。
result="$(run_launcher solo "claude codex")"
assert_eq "$(printf '%s' "$result" | sed -n '1p')" "1" \
  "先頭環境の AGENT_ENV_AGENTS を継承していても、claude を持たない環境は止める"
assert_eq "$(printf '%s' "$result" | sed -n '3p')" "0" \
  "同上: herdr を呼ばない"

# --- claude を持つ環境では従来どおり起動する ---
result="$(run_launcher default)"
assert_eq "$(printf '%s' "$result" | sed -n '1p')" "0" \
  "claude を持つ環境では 0 で終わる"
assert_eq "$(printf '%s' "$result" | sed -n '3p')" "2" \
  "claude を持つ環境では herdr を 2 回呼ぶ（tab create と pane run）"

# --- 定義に無いセッション名と未設定は先頭環境として扱う（agent-environments.zsh と同じ） ---
result="$(run_launcher nosuchsession)"
assert_eq "$(printf '%s' "$result" | sed -n '1p')" "0" \
  "定義に無いセッション名は先頭環境へ落ちる"
result="$(run_launcher -)"
assert_eq "$(printf '%s' "$result" | sed -n '1p')" "0" \
  "HERDR_SESSION 未設定は先頭環境へ落ちる"
assert_eq "$(printf '%s' "$result" | sed -n '3p')" "2" \
  "HERDR_SESSION 未設定でも herdr を呼ぶ"

# --- 展開結果の健全性 ---
script_body="$(cat "$SCRIPT")"
assert_contains "$script_body" "set -euo pipefail" "set -euo pipefail がある"
assert_not_contains "$script_body" "{{" "未展開のテンプレート構文が残っていない"

# --- 環境名がソースに漏れていない ---
tmpl="$(cat "$CHEZMOI_SOURCE/private_dot_config/herdr/executable_launch-claude-tab.sh.tmpl")"
assert_not_contains "$tmpl" "secondary" "テンプレートに固定の環境名が残っていない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
