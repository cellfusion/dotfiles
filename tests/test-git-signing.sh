#!/usr/bin/env bash
# Secure Enclave 鍵による git 署名まわりの設定を検証する。
set -u
# shellcheck source=lib/assert.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"

zshrc="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshrc")"

# --- SSH_AUTH_SOCK は $HOME で書く ---
# ダブルクォート内の ~ は展開されないため、リテラルの ~ を含む export は不正である。
assert_not_contains "$zshrc" 'SSH_AUTH_SOCK="~/' \
  "zshrc: SSH_AUTH_SOCK にクォート内の ~ を使わない"
assert_contains "$zshrc" 'SSH_AUTH_SOCK="$HOME/Library/Group Containers' \
  "zshrc: SSH_AUTH_SOCK を \$HOME で書く"

# --- git 署名の provider ラッパー ---
wrapper_src="$CHEZMOI_SOURCE/private_dot_local/bin/executable_git-ssh-sign"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$wrapper_src" ]; then
  _pass "wrapper: executable_git-ssh-sign がある"
else
  _fail "wrapper: executable_git-ssh-sign がある" "見つからない: $wrapper_src"
fi

wrapper="$(cat "$wrapper_src" 2>/dev/null || true)"
assert_contains "$wrapper" 'SSH_SK_PROVIDER=/usr/lib/ssh-keychain.dylib' \
  "wrapper: Secure Enclave の provider を設定する"
assert_contains "$wrapper" 'exec /usr/bin/ssh-keygen "$@"' \
  "wrapper: 引数をそのまま ssh-keygen へ渡す"

# --- Secure Enclave 鍵のプロビジョニングスクリプト ---
prov_src="$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_80-secure-enclave-keys.sh.tmpl"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$prov_src" ]; then
  _pass "provision: 80-secure-enclave-keys がある"
else
  _fail "provision: 80-secure-enclave-keys がある" "見つからない: $prov_src"
fi

prov="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" < "$prov_src" 2>&1 || true)"

assert_contains "$prov" 'sc_auth create-ctk-identity' "provision: identity を作る"
assert_contains "$prov" 'p-256-ne' "provision: non-exportable の鍵種別を使う"
assert_contains "$prov" '-t none' "provision: 生体認証を要求しない"
assert_contains "$prov" 'github-auth' "provision: 認証鍵の label を持つ"
assert_contains "$prov" 'github-sign' "provision: 署名鍵の label を持つ"
assert_contains "$prov" 'id_github_auth' "provision: 認証鍵の stub 先を持つ"
assert_contains "$prov" 'id_github_sign' "provision: 署名鍵の stub 先を持つ"
assert_contains "$prov" '/usr/lib/ssh-keychain.dylib' "provision: provider のパスを持つ"
assert_contains "$prov" 'ssh-keygen -K' "provision: stub file を書き出す"
assert_contains "$prov" 'list-ctk-identities' "provision: 既存 identity を調べてから作る"
assert_not_contains "$prov" 'BEGIN OPENSSH PRIVATE KEY' "provision: 秘密鍵を含まない"

# --- 承認ゲート: chezmoi ソース側に ask ルールがある ---
# ~/.config/claude/settings.json は chezmoi 管理下 (private_settings.json.tmpl) なので、
# 実ファイルを直接編集しても apply で上書きされる。ソース側が唯一の記録である。
settings="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  < "$CHEZMOI_SOURCE/private_dot_config/claude/private_settings.json.tmpl" 2>&1 || true)"

for r in 'Bash(git push *)' 'Bash(gh pr create *)' 'Bash(gh pr merge *)' \
         'Bash(gh release create *)' 'Bash(gh repo delete *)'; do
  assert_contains "$settings" "$r" "gate: ask ルールがある: $r"
done

# gh api は 2026-08-27 に ask から外した。読み取りの呼び出しにも一致してしまい、
# 調査のたびにプロンプトが出ていたためである。書き込みだけを狙うルールは書けないので、
# gh api の書き込みはゲートを通らない。戻すなら doc の承認ゲートの節も一緒に直す。
assert_not_contains "$settings" 'Bash(gh api *)' "gate: gh api は ask に入れない"

# --- docs に apply 後の手順が記録されている ---
# ~/.ssh/config と ~/.config/git/config は chezmoi 管理外なので apply では入らない。
# 手で入れる内容がここに無いと、新マシンで再現できない。
doc_path="$CHEZMOI_SOURCE/private_dot_config/docs/git-signing.md"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$doc_path" ]; then
  _pass "docs: git-signing.md がある"
else
  _fail "docs: git-signing.md がある" "見つからない: $doc_path"
fi

doc="$(cat "$doc_path" 2>/dev/null || true)"

for s in "apply 後の手順" "承認ゲート" "ssh の設定" "git の設定" \
         "動作確認" "鍵の更新" "鍵を失ったとき" "トレードオフ"; do
  assert_contains "$doc" "## $s" "docs: $s の節がある"
done

# apply では入らない設定の全文が載っている
assert_contains "$doc" "IdentityAgent none" "docs: ssh の IdentityAgent を写している"
assert_contains "$doc" "SecurityKeyProvider /usr/lib/ssh-keychain.dylib" \
  "docs: ssh の SecurityKeyProvider を写している"
assert_contains "$doc" "id_github_auth" "docs: 認証鍵の stub パスを写している"
assert_contains "$doc" "id_github_sign.pub" "docs: 署名鍵の公開鍵パスを写している"
assert_contains "$doc" "format = ssh" "docs: gpg.format を写している"
assert_contains "$doc" "gpgsign = true" "docs: commit.gpgsign を写している"
assert_contains "$doc" "git-ssh-sign" "docs: provider ラッパーを写している"

# 承認ゲートの 6 件
for r in "Bash(git push *)" "Bash(gh repo delete *)"; do
  assert_contains "$doc" "$r" "docs: ask ルールを写している: $r"
done
# 外したルールを doc の ask 一覧に残さない。設定とドキュメントが食い違う。
gate_json="$(printf '%s\n' "$doc" | sed -n '/^"ask": \[/,/^\]/p')"
assert_not_contains "$gate_json" 'Bash(gh api *)' \
  "docs: ask の一覧に gh api を残さない"

# 鍵の生成元を指している
assert_contains "$doc" "run_onchange_after_80-secure-enclave-keys" \
  "docs: プロビジョニングスクリプトを指している"

# 固有識別子を書かない
assert_not_contains "$doc" "/Users/" "docs: ユーザー名を含む絶対パスを書かない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
