#!/usr/bin/env bash
# Paseo プラグイン pr-review のソース構成を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

plugin_dir="$CHEZMOI_SOURCE/private_dot_local/share/paseo-plugins/pr-review"

for name in paseo-plugin.json package.json tsconfig.json contracts.ts; do
  assert_eq "$([ -f "$plugin_dir/$name" ] && echo yes || echo no)" "yes" \
    "paseo-plugin: $name がある"
done

manifest="$(cat "$plugin_dir/paseo-plugin.json" 2>/dev/null || echo '{}')"
assert_eq "$(printf '%s' "$manifest" | jq -r '.id // "none"')" "pr-review" \
  "paseo-plugin: manifest の id が pr-review である"

pkg="$(cat "$plugin_dir/package.json" 2>/dev/null || echo '{}')"
assert_eq "$(printf '%s' "$pkg" | jq -r '.scripts.typecheck // "none"')" "tsc --noEmit" \
  "paseo-plugin: typecheck スクリプトがある"
assert_eq "$(printf '%s' "$pkg" | jq -r '.devDependencies["@getpaseo/plugin"] // "none"')" "0.7.2" \
  "paseo-plugin: プラグイン SDK のバージョンを固定する"

contracts="$(cat "$plugin_dir/contracts.ts" 2>/dev/null || true)"
assert_contains "$contracts" "listPullRequests" "paseo-plugin: PR 一覧の RPC 契約がある"
assert_contains "$contracts" "preparePullRequest" "paseo-plugin: 起動準備の RPC 契約がある"
assert_contains "$contracts" "instructionsChanged" "paseo-plugin: 指示ファイルの変更有無を返す"

gitignore="$(cat "$CHEZMOI_SOURCE/.gitignore" 2>/dev/null || true)"
assert_contains "$gitignore" "paseo-plugins/pr-review/node_modules" \
  "paseo-plugin: node_modules を git 追跡から外す"

for name in commands.ts index.ts; do
  assert_eq "$([ -f "$plugin_dir/$name" ] && echo yes || echo no)" "yes" \
    "paseo-plugin: $name がある"
done

commands="$(cat "$plugin_dir/commands.ts" 2>/dev/null || true)"
assert_contains "$commands" "/opt/homebrew/bin" \
  "paseo-plugin: daemon の PATH に Homebrew を足す"
assert_contains "$commands" "execFile" "paseo-plugin: shell を経由せずに実行する"

index="$(cat "$plugin_dir/index.ts" 2>/dev/null || true)"
assert_contains "$index" "plugin.handle(listPullRequests" \
  "paseo-plugin: PR 一覧の RPC を登録する"
assert_contains "$index" "plugin.handle(preparePullRequest" \
  "paseo-plugin: 起動準備の RPC を登録する"
assert_contains "$index" "gh pr diff" "paseo-plugin: gh pr diff で変更パスを取る"
assert_contains "$index" "CLAUDE.md" "paseo-plugin: 指示ファイルを検査する"
assert_contains "$index" ".agents/" "paseo-plugin: .agents 配下も検査する"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
