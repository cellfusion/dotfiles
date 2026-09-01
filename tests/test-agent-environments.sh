#!/usr/bin/env bash
# agent-environments.zsh.tmpl を展開して zsh で source し、
# 環境解決とツールガードの挙動を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

# 環境定義は clone した人のマシンによって違うので、fixture を与えて描画する。
cfg="$(mktemp)"
cf_primary='0000000000000000''000000000000000a'
cf_work='0000000000000000''000000000000000b'
cat > "$cfg" <<EOF
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]
    cloudflareAccountId = "$cf_primary"

[[data.environments]]
    session = "work"
    label   = "P2"
    agents  = ["claude"]
    cloudflareAccountId = "$cf_work"

[[data.environments]]
    session = "solo"
    label   = "P3"
    agents  = ["codex"]
EOF

# 環境定義を持たないマシン（private-data.toml が無い場合）。
empty_cfg="$(mktemp)"
printf '[data]\n' > "$empty_cfg"

render() {
  chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$1" --config-format toml \
    < "$CHEZMOI_SOURCE/private_dot_config/zsh/agent-environments.zsh.tmpl"
}

ENV_ZSH="$(mktemp)"
render "$cfg" > "$ENV_ZSH"
EMPTY_ZSH="$(mktemp)"
render "$empty_cfg" > "$EMPTY_ZSH"
trap 'rm -f "$ENV_ZSH" "$EMPTY_ZSH" "$cfg" "$empty_cfg"' EXIT

# $1 の HERDR_SESSION で $3（既定は $ENV_ZSH）を source し、$2 を評価する。
# XDG_CONFIG_HOME はコマンド文字列の内側で設定する。/etc/zshenv が
# XDG_CONFIG_HOME="$HOME/.config" を無条件に export し、zsh -f でも読まれるため、
# 環境変数として前置しても上書きされてしまう。
run_env() {
  local file="${3:-$ENV_ZSH}"
  HERDR_SESSION="$1" zsh -f -c "XDG_CONFIG_HOME=/xdg; source '$file'; $2" 2>&1
}

# $1 の AGENT_ENV と $2 の HERDR_SESSION で $ENV_ZSH を source し、$3 を評価する。
# run_env と同じ理由で XDG_CONFIG_HOME はコマンド文字列の内側で設定する。
run_env_both() {
  AGENT_ENV="$1" HERDR_SESSION="$2" zsh -f -c "XDG_CONFIG_HOME=/xdg; source '$ENV_ZSH'; $3" 2>&1
}

# --- 先頭環境（primary）はサフィックスの無いパスを使う ---
assert_eq "$(run_env default 'echo $CLAUDE_CONFIG_DIR')" "/xdg/claude" \
  "先頭環境の CLAUDE_CONFIG_DIR は ~/.config/claude"
assert_eq "$(run_env default 'echo $CODEX_HOME')" "/xdg/codex" \
  "先頭環境の CODEX_HOME は ~/.config/codex"
assert_eq "$(run_env default 'echo $WRANGLER_HOME')" "/xdg/.wrangler" \
  "先頭環境の WRANGLER_HOME は ~/.config/.wrangler"

# --- 2 つ目以降は _<session> サフィックスを使う ---
assert_eq "$(run_env work 'echo $CLAUDE_CONFIG_DIR')" "/xdg/claude_work" \
  "2 つ目の CLAUDE_CONFIG_DIR は suffix 付き"
assert_eq "$(run_env work 'echo $WRANGLER_HOME')" "/xdg/.wrangler-work" \
  "2 つ目の WRANGLER_HOME は -<session> 付き"
assert_eq "$(run_env solo 'echo $CODEX_HOME')" "/xdg/codex_solo" \
  "3 つ目の CODEX_HOME は suffix 付き"

# --- agents に無いツールの変数は持たない ---
assert_eq "$(run_env work 'echo $CODEX_HOME')" "" \
  "codex を持たない環境は CODEX_HOME を持たない"
assert_eq "$(run_env solo 'echo $CLAUDE_CONFIG_DIR')" "" \
  "claude を持たない環境は CLAUDE_CONFIG_DIR を持たない"

# --- agents に無いツールは関数で覆い、primary にもツール既定にも落とさない ---
assert_eq "$(run_env work 'echo ${+functions[codex]}')" "1" \
  "持たないツールを関数で覆う"
assert_eq "$(run_env work 'echo ${+functions[claude]}')" "0" \
  "持つツールは関数で覆わない"
assert_eq "$(run_env work 'codex >/dev/null 2>&1; echo $?')" "1" \
  "覆ったツールは非ゼロで終わる"
assert_contains "$(run_env work 'codex 2>&1 >/dev/null')" "not configured" \
  "覆ったツールは警告を出す"
assert_contains "$(run_env work 'codex 2>&1 >/dev/null')" "work" \
  "警告に環境名が入る"
assert_eq "$(run_env solo 'echo ${+functions[claude]}')" "1" \
  "codex だけの環境では claude を覆う"

# --- 未定義名と未設定は先頭環境へ落ちる。警告は出さない ---
assert_eq "$(run_env nosuchsession 'echo $AGENT_ENV_SESSION')" "default" \
  "定義の無いセッション名は先頭環境へ落ちる"
assert_eq "$(run_env '' 'echo $AGENT_ENV_SESSION')" "default" \
  "HERDR_SESSION 未設定は先頭環境へ落ちる"
assert_eq "$(run_env nosuchsession 'echo $CLAUDE_CONFIG_DIR')" "/xdg/claude" \
  "フォールバック後は先頭環境の値になる"
assert_eq "$(run_env nosuchsession ':')" "" \
  "フォールバックは警告を出さない"

# --- AGENT_ENV は HERDR_SESSION より優先する ---
# Paseo は HERDR_SESSION を注入しない。provider 定義が AGENT_ENV を注入する。
assert_eq "$(run_env_both work '' 'echo $AGENT_ENV_SESSION')" "work" \
  "AGENT_ENV が定義済みの環境名ならその環境に解決する"
assert_eq "$(run_env_both work default 'echo $AGENT_ENV_SESSION')" "work" \
  "両方あるとき AGENT_ENV が優先する"
assert_eq "$(run_env_both '' work 'echo $AGENT_ENV_SESSION')" "work" \
  "AGENT_ENV が空なら HERDR_SESSION を使う"
assert_eq "$(run_env_both nosuchsession '' 'echo $AGENT_ENV_SESSION')" "default" \
  "AGENT_ENV が定義に無い名前なら先頭環境へ落ちる"
assert_eq "$(run_env_both '' '' 'echo $AGENT_ENV_SESSION')" "default" \
  "どちらも未設定なら先頭環境へ落ちる"
assert_eq "$(run_env_both work '' 'echo $CLAUDE_CONFIG_DIR')" "/xdg/claude_work" \
  "AGENT_ENV で解決した環境のパスが使われる"
assert_eq "$(run_env_both work '' 'echo $CODEX_HOME')" "" \
  "AGENT_ENV で解決しても agents の制限が効く"

# --- AGENT_ENV_* を export する ---
assert_eq "$(run_env work 'echo $AGENT_ENV_AGENTS')" "claude" \
  "AGENT_ENV_AGENTS はスペース区切りの agent 名"
assert_eq "$(run_env default 'echo $AGENT_ENV_AGENTS')" "claude codex" \
  "AGENT_ENV_AGENTS は定義順に並ぶ"

# --- Cloudflare のアカウント ID ---
assert_eq "$(run_env default 'echo $CLOUDFLARE_ACCOUNT_ID')" \
  "$cf_primary" "先頭環境の Cloudflare ID"
assert_eq "$(run_env solo 'echo $CLOUDFLARE_ACCOUNT_ID')" "" \
  "cloudflareAccountId 未指定なら export しない"

# --- 環境定義が無いマシンでも壊れない ---
assert_eq "$(run_env '' 'echo $AGENT_ENV_SESSION' "$EMPTY_ZSH")" "default" \
  "定義が無い場合は default 環境 1 つとして描画する"
assert_eq "$(run_env '' 'echo $CLAUDE_CONFIG_DIR' "$EMPTY_ZSH")" "/xdg/claude" \
  "定義が無い場合も claude は使える"
assert_eq "$(run_env '' 'echo $AGENT_ENV_AGENTS' "$EMPTY_ZSH")" "claude codex" \
  "定義が無い場合は claude と codex の両方を持つ"

# --- 環境名がソースに漏れていない ---
tmpl="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/agent-environments.zsh.tmpl")"
assert_not_contains "$tmpl" "secondary" \
  "テンプレートに固定の環境名が残っていない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
