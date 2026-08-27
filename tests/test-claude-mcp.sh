#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# modify_dot_claude.json.tmpl を展開して実行し、stdin に流した .claude.json の
# 変換結果を返す。第 2 引数で source 側のディレクトリを切り替える（省略時は claude 本体）。
run_modify() {
  local tmp out src
  src="${2:-private_dot_config/claude}"
  tmp="$(mktemp)"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    < "$CHEZMOI_SOURCE/$src/modify_dot_claude.json.tmpl" > "$tmp" 2>/dev/null
  chmod +x "$tmp"
  out="$(printf '%s' "$1" | "$tmp" 2>&1)"
  rm -f "$tmp"
  printf '%s' "$out"
}

# 実ファイルに近い形の入力。削除対象 2 件と Cloudflare プラグイン MCP を持つ。
# 削除対象は消え、Cloudflare MCP だけ残る。
SAMPLE='{
  "mcpServers": {
    "cairn": {
      "type": "stdio",
      "command": "cairn-mcp"
    },
    "zk": {
      "type": "stdio",
      "command": "zk-mcp"
    },
    "plugin:cloudflare:cloudflare-api": {
      "type": "stdio",
      "command": "cloudflare-mcp"
    }
  },
  "someRuntimeState": "keep-me"
}'

out="$(run_modify "$SAMPLE")"

assert_eq "$(printf '%s' "$out" | jq -r '.mcpServers | has("cairn")')" "false" \
  "cairn を削除する"
assert_eq "$(printf '%s' "$out" | jq -r '.mcpServers | has("zk")')" "false" \
  "zk を削除する"
assert_eq "$(printf '%s' "$out" | jq -r '.mcpServers | has("plugin:cloudflare:cloudflare-api")')" "true" "Cloudflare MCP を維持する"
assert_eq "$(printf '%s' "$out" | jq -r '.someRuntimeState')" "keep-me" "mcpServers 以外のランタイム状態を保持する"

# 削除対象リストの全項目。全件が消える。
LEGACY='{
  "mcpServers": {
    "cairn": { "type": "stdio", "command": "cairn-mcp" },
    "zk": { "type": "stdio", "command": "zk-mcp" },
    "relay": { "type": "stdio", "command": "relay-mcp" },
    "obsidian": { "type": "stdio", "command": "obsidian-mcp" },
    "obsidian-mcp-pro": { "type": "stdio", "command": "obsidian-mcp-pro" }
  }
}'
legacy_out="$(run_modify "$LEGACY")"
assert_eq "$(printf '%s' "$legacy_out" | jq -r '.mcpServers | length')" "0" \
  "削除対象（cairn/zk/relay/obsidian/obsidian-mcp-pro）を全て削除する"

# mcpServers キー自体が存在しない入力でも壊れない。
NO_MCP='{ "someRuntimeState": "keep-me" }'
no_mcp_out="$(run_modify "$NO_MCP")"
assert_eq "$(printf '%s' "$no_mcp_out" | jq -r '.someRuntimeState')" "keep-me" \
  "mcpServers キーが無い入力でも壊れない"
assert_eq "$(printf '%s' "$no_mcp_out" | jq -r '.mcpServers')" "{}" \
  "mcpServers キーが無い入力でも空の mcpServers を持つ結果になる"

# 空入力（ファイルが存在しない場合）でも壊れない。
empty_out="$(run_modify "")"
assert_eq "$(printf '%s' "$empty_out" | jq -r '.mcpServers')" "{}" \
  "空入力でも空の mcpServers を持つ結果になる"

# 追加するサーバー定義は空なので、削除対象を除いたキーは変換で増えない。
assert_eq "$(printf '%s' "$out" | jq -r '.mcpServers | keys | length')" "1" \
  "追加サーバーが空なので削除後の MCP は増えない（Cloudflare MCP のみ残る）"

# ~/.claude.json（リポジトリ直下の modify script）も同じ変換結果になる。
root_out="$(run_modify "$SAMPLE" .)"
assert_eq "$root_out" "$out" "リポジトリ直下（~/.claude.json）の変換結果が claude 本体と同じになる"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
