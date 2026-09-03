#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# modify_ スクリプトを展開して実行し、stdin に流した config の変換結果を返す。
# 第 2 引数で source 側のディレクトリを切り替える（省略時は codex 本体）。
run_modify() {
  local tmp out src
  src="${2:-private_dot_config/codex}"
  tmp="$(mktemp)"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    < "$CHEZMOI_SOURCE/$src/modify_private_config.toml.tmpl" > "$tmp" 2>/dev/null
  chmod +x "$tmp"
  out="$(printf '%s' "$1" | "$tmp" 2>&1)"
  rm -f "$tmp"
  printf '%s' "$out"
}

# 実ファイルに近い形の入力。トップレベルのキー、[tools]、[projects]、[mcp_servers] を持つ。
SAMPLE='model = "gpt-5.2-codex"
model_reasoning_effort = "medium"
approval_policy = "never"
approvals_reviewer = "user"
sandbox_mode = "danger-full-access"

notify = ["/path/to/notifier", "turn-ended"]

[sandbox_workspace_write]
network_access = true

[tools]
web_search = true

[projects."/Users/someone/work/repo"]
trust_level = "trusted"

[projects."/Users/someone"]
trust_level = "untrusted"

[mcp_servers.context7]
command = "npx"
args = [ "-y", "@upstash/context7-mcp@latest" ]

[mcp_servers.fetch]
command = "uvx"
args = [ "mcp-server-fetch" ]

[mcp_servers.playwright]
command = "npx"
args = [ "-y", "@playwright/mcp@latest" ]

[mcp_servers.serena]
command = "uvx"
args = [ "serena" ]

[mcp_servers.serena.env]
SERENA_LOG_LEVEL = "info"

[mcp_servers.unityMCP]
command = "uv"
args = [ "run", "unity-mcp" ]

[mcp_servers.node_repl]
command = "node_repl"

[mcp_servers.sites-design-picker]
command = "sites-design-picker"
'

out="$(run_modify "$SAMPLE")"

# 1. トップレベルの model が最新のものに置換される。
assert_contains "$out" 'model = "gpt-5.6-terra"' "model を gpt-5.6-terra に置換する"
assert_not_contains "$out" 'gpt-5.2-codex' "古い model が残らない"

# 2. model_reasoning_effort が設定される。
assert_contains "$out" 'model_reasoning_effort = "medium"' "effort を medium にする"

# 3. automode の推奨設定に置換される。
assert_contains "$out" 'approval_policy = "on-request"' "承認ポリシーを on-request にする"
assert_contains "$out" 'approvals_reviewer = "auto_review"' "承認判定を auto reviewer に委任する"
assert_contains "$out" 'sandbox_mode = "workspace-write"' "sandbox を workspace-write にする"
assert_contains "$out" '[sandbox_workspace_write]' "sandbox_workspace_write セクションを作る"
assert_contains "$out" 'network_access = false' "sandbox 内ネットワークを無効にする"
assert_not_contains "$out" 'approval_policy = "never"' "危険な承認ポリシーを残さない"
assert_not_contains "$out" 'sandbox_mode = "danger-full-access"' "危険な sandbox 設定を残さない"

# 4. 実ファイル側の内容がそのまま通る。
assert_contains "$out" '[projects."/Users/someone/work/repo"]' "projects のセクションが残る"
assert_contains "$out" 'trust_level = "untrusted"' "trust_level が残る"
assert_contains "$out" 'notify = ["/path/to/notifier", "turn-ended"]' "notify が残る"
assert_contains "$out" 'web_search = true' "tools の中身が残る"

# 4b. 不要な mcp_servers は除外し、Codex 公式のものは維持する。
assert_not_contains "$out" '[mcp_servers.context7]' "context7 を削除する"
assert_not_contains "$out" '[mcp_servers.fetch]' "fetch を削除する"
assert_not_contains "$out" '[mcp_servers.playwright]' "playwright を削除する"
assert_not_contains "$out" '[mcp_servers.serena]' "serena を削除する"
assert_not_contains "$out" '[mcp_servers.unityMCP]' "unityMCP を削除する"
assert_not_contains "$out" '[mcp_servers.serena.env]' "削除対象の子テーブルも削除する"
assert_not_contains "$out" '@upstash/context7-mcp@latest' "削除対象の中身も残らない"
assert_contains "$out" '[mcp_servers.node_repl]' "Codex 公式 node_repl を維持する"
assert_contains "$out" '[mcp_servers.sites-design-picker]' "Codex 公式 sites-design-picker を維持する"

# 5. セクション内の model キーは誤爆させない。
NESTED='model = "gpt-5.2-codex"

[mcp_servers.somesrv]
model = "should-not-change"
'
nested_out="$(run_modify "$NESTED")"
assert_contains "$nested_out" 'model = "should-not-change"' "セクション内の model は書き換えない"
assert_contains "$nested_out" 'model = "gpt-5.6-terra"' "トップレベルの model は書き換える"

# 5b. 前方一致の事故を避ける: serena は消すが serena-extra は残す。
PREFIX='[mcp_servers.serena]
command = "uvx"

[mcp_servers.serena-extra]
command = "uvx"
'
prefix_out="$(run_modify "$PREFIX")"
assert_not_contains "$prefix_out" '[mcp_servers.serena]' "serena を削除する（前方一致で誤爆させない）"
assert_contains "$prefix_out" '[mcp_servers.serena-extra]' "serena-extra は残す"

# 5c. 削除対象の mcp テーブルが入力の最初のセクションでも、
# top-level キーがファイル末尾へ回らず TOML として妥当な位置に出力される。
FIRST_SECTION_MCP='model = "gpt-5.2-codex"

[mcp_servers.context7]
command = "npx"

[mcp_servers.node_repl]
command = "node_repl"
'
first_section_out="$(run_modify "$FIRST_SECTION_MCP")"
assert_not_contains "$first_section_out" '[mcp_servers.context7]' "先頭セクションが削除対象でも context7 を削除する"
assert_contains "$first_section_out" '[mcp_servers.node_repl]' "先頭セクションが削除対象でも node_repl は残す"
assert_contains "$first_section_out" 'approval_policy = "on-request"' "先頭セクションが削除対象でも top-level キーが補われる"
first_tmp_toml="$(mktemp)"
printf '%s' "$first_section_out" > "$first_tmp_toml"
first_parsed="$(python3 -c "
import tomllib
d = tomllib.load(open('$first_tmp_toml','rb'))
print('ok', len(d['mcp_servers']))
" 2>&1)"
rm -f "$first_tmp_toml"
assert_eq "$first_parsed" "ok 1" "先頭セクションが削除対象でも出力全体が TOML としてパースできる"

# 6. 該当行が無い入力でも、推奨設定が追加される。
NOKEY='notify = ["x"]

[tools]
web_search = true
'
nokey_out="$(run_modify "$NOKEY")"
assert_contains "$nokey_out" 'model = "gpt-5.6-terra"' "model 行が無ければ追加する"
assert_contains "$nokey_out" 'model_reasoning_effort = "medium"' "effort 行が無ければ追加する"
assert_contains "$nokey_out" 'approval_policy = "on-request"' "approval_policy 行が無ければ追加する"
assert_contains "$nokey_out" 'approvals_reviewer = "auto_review"' "approvals_reviewer 行が無ければ追加する"
assert_contains "$nokey_out" 'sandbox_mode = "workspace-write"' "sandbox_mode 行が無ければ追加する"
assert_contains "$nokey_out" 'network_access = false' "network_access 行が無ければ追加する"
assert_contains "$nokey_out" 'web_search = true' "追加しても既存の内容は壊さない"

# 7. 空の入力（ファイルが存在しない場合）でも最小の config を出す。
empty_out="$(run_modify "")"
assert_contains "$empty_out" 'model = "gpt-5.6-terra"' "空入力で model を出す"
assert_contains "$empty_out" 'model_reasoning_effort = "medium"' "空入力で effort を出す"
assert_contains "$empty_out" 'approval_policy = "on-request"' "空入力で approval_policy を出す"
assert_contains "$empty_out" 'approvals_reviewer = "auto_review"' "空入力で approvals_reviewer を出す"
assert_contains "$empty_out" 'sandbox_mode = "workspace-write"' "空入力で sandbox_mode を出す"
assert_contains "$empty_out" 'network_access = false' "空入力で network_access を出す"

# 8. 推奨設定は重複せず、出力が TOML として妥当である。
assert_eq "$(printf '%s\n' "$out" | grep -c '^approval_policy =')" "1" "approval_policy を重複させない"
assert_eq "$(printf '%s\n' "$out" | grep -c '^approvals_reviewer =')" "1" "approvals_reviewer を重複させない"
assert_eq "$(printf '%s\n' "$out" | grep -c '^sandbox_mode =')" "1" "sandbox_mode を重複させない"
assert_eq "$(printf '%s\n' "$out" | grep -c '^\[sandbox_workspace_write\]$')" "1" "sandbox セクションを重複させない"
assert_eq "$(printf '%s\n' "$out" | grep -c '^network_access =')" "1" "network_access を重複させない"

tmp_toml="$(mktemp)"
printf '%s' "$out" > "$tmp_toml"
parsed="$(python3 -c "
import tomllib
d = tomllib.load(open('$tmp_toml','rb'))
print(d['model'], d['model_reasoning_effort'], d['approval_policy'], d['approvals_reviewer'], d['sandbox_mode'], d['sandbox_workspace_write']['network_access'], len(d['projects']), len(d['mcp_servers']))
" 2>&1)"
rm -f "$tmp_toml"
assert_eq "$parsed" "gpt-5.6-terra medium on-request auto_review workspace-write False 2 2" "出力が TOML としてパースでき、他のセクションが保たれる"

# 9. CODEX_HOME は herdr セッションごとに切り替える。
zshrc="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshrc")"
assert_not_contains "$zshrc" "CODEX_HOME" \
  "dot_zshrc は CODEX_HOME を定義しない（agent-environments.zsh の値を上書きしてしまう）"

# 環境定義が無いマシンでも先頭環境は ~/.config/codex を使う。
empty_cfg="$(mktemp)"
printf '[data]\n' > "$empty_cfg"
default_env="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  --config "$empty_cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/private_dot_config/zsh/agent-environments.zsh.tmpl")"
rm -f "$empty_cfg"
assert_contains "$default_env" 'export CODEX_HOME="$XDG_CONFIG_HOME/codex"' \
  "先頭環境は ~/.config/codex を使う"

# 11. usage helper と Claude statusline の対象パスが存在する。
assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/sketchybar/helpers/executable_usage.sh.tmpl" ] && echo yes)" "yes" \
  "sketchybar usage helper が存在する"
assert_eq "$([ -f "$CHEZMOI_SOURCE/private_dot_config/claude/executable_statusline.sh" ] && echo yes)" "yes" \
  "Claude statusline が存在する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
