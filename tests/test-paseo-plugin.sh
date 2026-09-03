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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
