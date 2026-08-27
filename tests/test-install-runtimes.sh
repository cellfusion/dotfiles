#!/usr/bin/env bash
# npm / cargo / mise のマニフェストを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

npm_manifest="$(cat "$CHEZMOI_SOURCE/private_dot_config/install/npm-globals.txt" 2>&1)"
cargo_manifest="$(cat "$CHEZMOI_SOURCE/private_dot_config/install/cargo-globals.txt" 2>&1)"
mise_config="$(cat "$CHEZMOI_SOURCE/private_dot_config/mise/config.toml" 2>&1)"

# --- npm グローバル ---
for p in wrangler firebase-tools mcp-hub; do
  assert_contains "$npm_manifest" "$p" "npm: $p を載せる"
done
for p in openclaw corepack generator-code "@github/copilot" "@zed-industries"; do
  assert_not_contains "$npm_manifest" "$p" "npm: 削除候補の $p を載せない"
done

# --- cargo ---
for p in zellij zoxide spotify_player openapi-tui bottom feedr yashiki dioxus; do
  assert_not_contains "$cargo_manifest" "$p" "cargo: 削除候補の $p を載せない"
done

# --- mise ---
assert_contains "$mise_config" "[tools]" "mise: [tools] テーブルがある"
for t in python node pnpm java deno go; do
  assert_contains "$mise_config" "$t = " "mise: $t を管理する"
done

# 各行が形式に従っている(コメントと空行を除く)。
cargo_bad="$(grep -vE '^(#|$)' "$CHEZMOI_SOURCE/private_dot_config/install/cargo-globals.txt" 2>/dev/null \
  | grep -vE '^[a-zA-Z0-9_-]+\|.+$' || true)"
assert_eq "$cargo_bad" "" "cargo: 全行が <バイナリ名>|<引数> 形式"

cargo_entries="$(grep -vE '^(#|$)' "$CHEZMOI_SOURCE/private_dot_config/install/cargo-globals.txt" 2>/dev/null || true)"
assert_eq "$cargo_entries" "" "cargo: マニフェストが空である"

npm_bad="$(grep -vE '^(#|$)' "$CHEZMOI_SOURCE/private_dot_config/install/npm-globals.txt" 2>/dev/null \
  | grep -E '\s' || true)"
assert_eq "$npm_bad" "" "npm: 各行に空白が無い"

# --- mise の activate は PATH に任せる ---
# Brewfile は brew "mise" を入れる。zshrc が特定マシンの絶対パスを直書きしていると、
# 新マシンでは参照先が存在せず activate に失敗し、node / pnpm / java / deno が
# 有効にならないまま 40-npm-globals の前提も崩れる。
zshrc="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshrc" 2>&1)"
user_path_prefix="/Users"
assert_not_contains "$zshrc" "$user_path_prefix/" \
  "zshrc: ユーザー固有の絶対パスを直書きしない"
assert_contains "$zshrc" 'eval "$(mise activate zsh)"' \
  "mise: PATH 上の mise で activate する"
assert_contains "$zshrc" 'command -v mise' \
  "mise: mise が無いときは activate を飛ばす"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
