#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_config/codex/rules/modify_default.rules.tmpl"

BEGIN='# chezmoi-managed-begin'
END='# chezmoi-managed-end'

# modify_ スクリプトを展開して実行し、stdin に流した rules の変換結果を返す。
run_modify() {
  local tmp out
  tmp="$(mktemp)"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" < "$SRC" > "$tmp" 2>/dev/null
  chmod +x "$tmp"
  out="$(printf '%s' "$1" | "$tmp" 2>&1)"
  rm -f "$tmp"
  printf '%s' "$out"
}

# 管理対象の規則。ここに挙げたものが、どの入力からでも 1 回ずつ出ることを確かめる。
MANAGED_RULES=(
  'prefix_rule(pattern=["vp", "remove"], decision="allow")'
  'prefix_rule(pattern=["vp", "run", "build"], decision="allow")'
  'prefix_rule(pattern=["git", "add"], decision="allow")'
  'prefix_rule(pattern=["git", "commit"], decision="allow")'
  'prefix_rule(pattern=["git", "diff", "--check"], decision="allow")'
  'prefix_rule(pattern=["pnpm", "typecheck"], decision="allow")'
  'prefix_rule(pattern=["pnpm", "test"], decision="allow")'
  'prefix_rule(pattern=["pnpm", "lint"], decision="allow")'
  'prefix_rule(pattern=["pnpm", "build"], decision="allow")'
  'prefix_rule(pattern=["chezmoi", "diff"], decision="allow")'
  'prefix_rule(pattern=["bash", "tests/run-tests.sh"], decision="allow")'
  'prefix_rule(pattern=["~/.agents/skills/subagent-driven-development/scripts/review-package"], decision="allow")'
  'prefix_rule(pattern=["~/.agents/skills/_shared/scripts/agent-docs-dir"], decision="allow")'
  'prefix_rule(pattern=["chezmoi", "apply"], decision="prompt")'
)

# --- 1. 空入力（ファイルがまだ無いマシン）でも管理対象の規則を出す ---
empty_out="$(run_modify "")"
assert_contains "$empty_out" "$BEGIN" "空入力でも囲みの開始行を出す"
assert_contains "$empty_out" "$END" "空入力でも囲みの終了行を出す"
for rule in "${MANAGED_RULES[@]}"; do
  assert_contains "$empty_out" "$rule" "空入力で $rule を出す"
done

# apply は CLAUDE.md が明示の許可を要ると定めている。allow に昇格させない。
assert_not_contains "$empty_out" 'prefix_rule(pattern=["chezmoi", "apply"], decision="allow")' \
  "chezmoi apply を allow にしない"

# chezmoi execute-template はテンプレートの output 関数から任意の外部コマンドを
# 実行できる。allow は sandbox の外での実行まで許すので、管理対象に入れない。
assert_not_contains "$empty_out" 'prefix_rule(pattern=["chezmoi", "execute-template"]' \
  "chezmoi execute-template を管理対象に入れない"

# 規則以外の行が紛れ込んでいないこと。Starlark として読めない行があると
# Codex は rules の読み込みごと失敗する。
stray="$(printf '%s\n' "$empty_out" | grep -vE '^[[:space:]]*(#|$)' | grep -vcE '^(prefix_rule|network_rule)\(')"
assert_eq "$stray" "0" "コメントと空行以外は prefix_rule か network_rule の呼び出しだけになる"

# --- 2. 囲みの外の行を保つ ---
appended="$empty_out
prefix_rule(pattern=[\"cargo\", \"build\"], decision=\"allow\")"
appended_out="$(run_modify "$appended")"
assert_contains "$appended_out" 'prefix_rule(pattern=["cargo", "build"], decision="allow")' \
  "囲みの外に足された規則を残す"
for rule in "${MANAGED_RULES[@]}"; do
  assert_contains "$appended_out" "$rule" "追記があっても $rule を保つ"
done

# --- 3. Codex が承認の永続化で書き出す形の追記を保つ ---
CODEX_APPENDED="$empty_out

# network rule saved in execpolicy (2026-09-15)
network_rule(host=\"registry.npmjs.org\")"
codex_out="$(run_modify "$CODEX_APPENDED")"
assert_contains "$codex_out" 'network_rule(host="registry.npmjs.org")' \
  "Codex が追記した network_rule を残す"
assert_contains "$codex_out" '# network rule saved in execpolicy (2026-09-15)' \
  "Codex が追記したコメントを残す"

# --- 4. 冪等性: 2 回流しても結果が変わらない ---
twice_out="$(run_modify "$appended_out")"
assert_eq "$twice_out" "$appended_out" "2 回流しても結果が変わらない"
assert_eq "$(printf '%s\n' "$appended_out" | grep -cF "$BEGIN")" "1" "囲みの開始行を重複させない"
assert_eq "$(printf '%s\n' "$appended_out" | grep -cF "$END")" "1" "囲みの終了行を重複させない"

# --- 5. 囲みを持たない手書きのファイルを移行する ---
# 管理対象と同じ行が囲みの外にあれば落とす。落とさないと、囲みを導入した初回に
# 同じ規則が 2 回並ぶ。
HANDWRITTEN='prefix_rule(pattern=["vp", "remove"], decision="allow")
prefix_rule(pattern=["git", "add"], decision="allow")
prefix_rule(pattern=["git", "commit"], decision="allow")
prefix_rule(pattern=["cargo", "build"], decision="allow")'
migrated_out="$(run_modify "$HANDWRITTEN")"
assert_eq "$(printf '%s\n' "$migrated_out" | grep -cF 'prefix_rule(pattern=["git", "add"], decision="allow")')" "1" \
  "囲みが無い入力でも管理対象の規則を重複させない"
assert_eq "$(printf '%s\n' "$migrated_out" | grep -cF 'prefix_rule(pattern=["vp", "remove"], decision="allow")')" "1" \
  "囲みが無い入力でも vp の規則を重複させない"
assert_contains "$migrated_out" 'prefix_rule(pattern=["cargo", "build"], decision="allow")' \
  "囲みが無い入力でも管理対象でない規則は残す"
for rule in "${MANAGED_RULES[@]}"; do
  assert_contains "$migrated_out" "$rule" "囲みが無い入力から $rule を補う"
done

# --- 6. 2 つ目以降の AI 環境は本体の rules を symlink で共有する ---
script="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  < "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_90-agent-envs.sh.tmpl" 2>/dev/null)"
assert_contains "$script" 'link "../codex/rules" "$dir/rules"' \
  "setup_codex が rules を codex 本体へ向ける"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
