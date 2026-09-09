#!/usr/bin/env bash
# ~/.config/claude/settings.json（chezmoi ソース: private_settings.json.tmpl）の
# permissions を検証する。エージェントの成果物が置かれる ~/docs を読み書きできること、
# 照合されないパス規則を書いていないことを見る。
set -u
. "$(dirname "$0")/lib/assert.sh"

TMPL="$CHEZMOI_SOURCE/private_dot_config/claude/private_settings.json.tmpl"

rendered="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" < "$TMPL" 2>&1)"

# テンプレートを展開した結果が JSON として読める。
assert_eq "$(printf '%s' "$rendered" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" \
          "yes" "settings のテンプレートが JSON として読める"

# ~/docs を作業ディレクトリの外のアクセス先として登録する。
assert_eq "$(printf '%s' "$rendered" |
  jq -r '[.permissions.additionalDirectories[]? | select(. == "~/docs")] | length')" \
  "1" "permissions.additionalDirectories に ~/docs がある"

# 読みも編集も許可する。additionalDirectories だけでは編集の可否が mode に左右される。
for r in 'Read(~/docs/**)' 'Edit(~/docs/**)'; do
  assert_eq "$(printf '%s' "$rendered" |
    jq -r --arg r "$r" '[.permissions.allow[]? | select(. == $r)] | length')" \
    "1" "permissions.allow に規則がある: $r"
done

# Write(...) のパス規則は照合されず、起動時に警告が出るので書かない。
assert_eq "$(printf '%s' "$rendered" |
  jq -r '[.permissions.allow[]? | select(startswith("Write("))] | length')" \
  "0" "permissions.allow に Write( で始まる規則が無い"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
