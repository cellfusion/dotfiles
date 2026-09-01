#!/usr/bin/env bash
# run_onchange_after_90-agent-envs.sh.tmpl を展開して fixture 上で実行し、
# 2 つ目以降の AI 環境ディレクトリが正しく作られることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

cfg="$(mktemp)"
cat > "$cfg" <<'EOF'
[[data.environments]]
    session = "default"
    label   = "P1"
    agents  = ["claude", "codex"]

[[data.environments]]
    session = "work"
    label   = "P2"
    agents  = ["claude"]

[[data.environments]]
    session = "solo"
    label   = "P3"
    agents  = ["codex"]
EOF

SCRIPT="$(mktemp)"
chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml \
  < "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_90-agent-envs.sh.tmpl" > "$SCRIPT"
fixture="$(mktemp -d)"
trap 'rm -rf "$SCRIPT" "$cfg" "$fixture"' EXIT

# 先頭環境のディレクトリは chezmoi 本体が配る。fixture では手で用意する。
mkdir -p "$fixture/claude/agents" "$fixture/claude/commands" "$fixture/claude/skills" \
         "$fixture/claude/hooks" "$fixture/codex/agents"
: > "$fixture/claude/CLAUDE.md"
: > "$fixture/claude/settings.json"
: > "$fixture/codex/AGENTS.md"

if XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1; then status=0; else status=$?; fi
assert_eq "$status" "0" "スクリプトが 0 で終わる"

# --- 展開結果の健全性 ---
script_body="$(cat "$SCRIPT")"
assert_contains "$script_body" "#!/usr/bin/env bash" "shebang がある"
assert_contains "$script_body" "set -eu" "set -eu がある"
assert_not_contains "$script_body" "{{" "未展開のテンプレート構文が残っていない"

# --- 先頭環境には触らない ---
# ls の並びはロケールに依るので、数だけ見る。用意した 6 エントリのままであること。
assert_eq "$(ls "$fixture/claude" | wc -l | tr -d ' ')" "6" \
  "先頭環境の ~/.config/claude にエントリを足さない"
assert_eq "$([ -e "$fixture/claude_default" ] && echo yes || echo no)" "no" \
  "先頭環境に対して claude_<session> を作らない"

# --- claude を持つ 2 つ目の環境 ---
for name in agents commands skills hooks CLAUDE.md settings.json; do
  assert_eq "$(readlink "$fixture/claude_work/$name")" "../claude/$name" \
    "claude_work: $name が claude 本体を指す"
done
assert_eq "$(jq -r 'type' < "$fixture/claude_work/.claude.json")" "object" \
  "claude_work: .claude.json が JSON オブジェクトになる"
assert_eq "$(jq -r '.mcpServers | type' < "$fixture/claude_work/.claude.json")" "object" \
  "claude_work: mcpServers を持つ"

# --- 空の .claude.json も初期化して MCP をマージする ---
: > "$fixture/claude_work/.claude.json"
if XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1; then empty_status=0; else empty_status=$?; fi
assert_eq "$empty_status" "0" "空の .claude.json があってもスクリプトが 0 で終わる"
assert_eq "$(jq -r 'type' < "$fixture/claude_work/.claude.json")" "object" \
  "空の .claude.json が JSON オブジェクトに初期化される"
assert_eq "$(jq -r '.mcpServers | type' < "$fixture/claude_work/.claude.json")" "object" \
  "空の .claude.json に mcpServers を持つ"

# --- codex を持たない環境には codex ディレクトリを作らない ---
assert_eq "$([ -e "$fixture/codex_work" ] && echo yes || echo no)" "no" \
  "codex を持たない環境に codex_<session> を作らない"

# --- codex だけの環境 ---
assert_eq "$(readlink "$fixture/codex_solo/agents")" "../codex/agents" \
  "codex_solo: agents が codex 本体を指す"
assert_eq "$(readlink "$fixture/codex_solo/AGENTS.md")" "../codex/AGENTS.md" \
  "codex_solo: AGENTS.md が codex 本体を指す"
assert_contains "$(cat "$fixture/codex_solo/config.toml")" "model = " \
  "codex_solo: config.toml に model が入る"
assert_eq "$([ -e "$fixture/claude_solo" ] && echo yes || echo no)" "no" \
  "claude を持たない環境に claude_<session> を作らない"

# --- 冪等性: 2 回目でも壊れない ---
XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "$?" "0" "2 回目の実行も 0 で終わる"
assert_eq "$(readlink "$fixture/claude_work/agents")" "../claude/agents" \
  "2 回目の実行後も symlink が保たれる"

# --- 定義から消えた環境は削除せず警告する ---
mkdir -p "$fixture/claude_gone"
warn="$(XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" 2>&1 >/dev/null)"
assert_contains "$warn" "claude_gone" "定義に無い環境を警告する"
assert_eq "$([ -d "$fixture/claude_gone" ] && echo yes || echo no)" "yes" \
  "定義に無い環境を削除しない"

# --- Paseo の provider に AGENT_ENV を注入する ---
# Paseo は HERDR_SESSION を注入しないので、provider の env が環境名を伝える。
paseo_cfg="$fixture/paseo-config.json"
cat > "$paseo_cfg" <<'EOF'
{
  "version": 1,
  "daemon": { "listen": "127.0.0.1:6767" },
  "agents": {
    "providers": {
      "copilot": { "enabled": false }
    }
  }
}
EOF
if PASEO_CONFIG_FILE="$paseo_cfg" XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1
then paseo_status=0; else paseo_status=$?; fi
assert_eq "$paseo_status" "0" "Paseo の設定があってもスクリプトが 0 で終わる"

assert_eq "$(jq -r '.agents.providers.claude.env.AGENT_ENV' < "$paseo_cfg")" "default" \
  "先頭環境: 組み込み claude に AGENT_ENV を足す"
assert_eq "$(jq -r '.agents.providers.codex.env.AGENT_ENV' < "$paseo_cfg")" "default" \
  "先頭環境: 組み込み codex に AGENT_ENV を足す"
assert_eq "$(jq -r '.agents.providers["claude-work"].extends' < "$paseo_cfg")" "claude" \
  "2 つ目: claude-work が claude を継承する"
assert_eq "$(jq -r '.agents.providers["claude-work"].env.AGENT_ENV' < "$paseo_cfg")" "work" \
  "2 つ目: claude-work に AGENT_ENV を足す"
assert_eq "$(jq -r '.agents.providers["claude-work"].env.CLAUDE_CONFIG_DIR' < "$paseo_cfg")" \
  "$fixture/claude_work" "2 つ目: claude-work に CLAUDE_CONFIG_DIR を足す"
assert_eq "$(jq -r '.agents.providers["claude-work"].label' < "$paseo_cfg")" "Claude (P2)" \
  "2 つ目: label に private-data.toml の label が入る"
assert_eq "$(jq -r '.agents.providers | has("codex-work")' < "$paseo_cfg")" "false" \
  "codex を持たない環境に codex-<session> を作らない"
assert_eq "$(jq -r '.agents.providers["codex-solo"].env.CODEX_HOME' < "$paseo_cfg")" \
  "$fixture/codex_solo" "3 つ目: codex-solo に CODEX_HOME を足す"
assert_eq "$(jq -r '.agents.providers | has("claude-solo")' < "$paseo_cfg")" "false" \
  "claude を持たない環境に claude-<session> を作らない"

# --- Paseo が書いた他の設定を壊さない ---
assert_eq "$(jq -r '.agents.providers.copilot.enabled' < "$paseo_cfg")" "false" \
  "他の provider を壊さない"
assert_eq "$(jq -r '.daemon.listen' < "$paseo_cfg")" "127.0.0.1:6767" \
  "daemon の設定を壊さない"
assert_eq "$(jq -r '.version' < "$paseo_cfg")" "1" "version を壊さない"

# --- 既存の env を消さない。2 回目でも壊れない ---
jq '.agents.providers["claude-work"].env.EXISTING = "keep"' < "$paseo_cfg" > "$paseo_cfg.t"
mv "$paseo_cfg.t" "$paseo_cfg"
PASEO_CONFIG_FILE="$paseo_cfg" XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1
assert_eq "$(jq -r '.agents.providers["claude-work"].env.EXISTING' < "$paseo_cfg")" "keep" \
  "既存の env のキーを消さない"
assert_eq "$(jq -r '.agents.providers["claude-work"].env.AGENT_ENV' < "$paseo_cfg")" "work" \
  "2 回目の実行後も AGENT_ENV が残る"

# --- Paseo の設定が無いマシンでは何もしない ---
missing_cfg="$fixture/no-such-paseo.json"
if PASEO_CONFIG_FILE="$missing_cfg" XDG_CONFIG_HOME="$fixture" bash "$SCRIPT" >/dev/null 2>&1
then missing_status=0; else missing_status=$?; fi
assert_eq "$missing_status" "0" "Paseo の設定が無くても 0 で終わる"
assert_eq "$([ -e "$missing_cfg" ] && echo yes || echo no)" "no" \
  "Paseo の設定が無いとき作らない"

# --- 環境名がソースに漏れていない ---
tmpl="$(cat "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_90-agent-envs.sh.tmpl")"
assert_not_contains "$tmpl" "secondary" "テンプレートに固定の環境名が残っていない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
