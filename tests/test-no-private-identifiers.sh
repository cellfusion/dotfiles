#!/usr/bin/env bash
# 作業ツリーのファイルに固有識別子が混入していないか検証する。
# --untracked を付けるのは、再汚染の典型経路が新規ファイルの追加だからである。
# -i を付けるのは、禁止語に大小混在の綴りがあるからである。
# 第1層: 形で検出する。パターンはリポジトリに書いてよい。
# 第2層: 語で検出する。語のリストは chezmoi data から取り、リポジトリには書かない。
set -u
# shellcheck source=lib/assert.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"

cd "$CHEZMOI_SOURCE" || exit 1

# このテスト自身と作業ディレクトリは検査から外す。
# 自身はパターン定義を含む。_cellfusion/ は gitignore 済みなので
# --exclude-standard で既に外れるが、念のため二重に外す。
exclude_self() {
  grep -v '^tests/test-no-private-identifiers.sh:' | grep -v '^_cellfusion/'
}

assert_no_match() {
  local pattern="$1" desc="$2" hits
  TESTS_RUN=$((TESTS_RUN + 1))
  hits="$(git grep -nIiE --untracked --exclude-standard "$pattern" -- . 2>/dev/null | exclude_self || true)"
  if [ -z "$hits" ]; then
    _pass "$desc"
  else
    _fail "$desc" "$(printf '%s' "$hits" | head -5)"
  fi
}

# --- 第1層: 形で検出する ---

assert_no_match '[0-9a-f]{32}' "32桁hexのアカウント識別子を含まない"
assert_no_match '-----BEGIN [A-Z ]*PRIVATE KEY' "秘密鍵を含まない"
assert_no_match '(sk-ant-|ghp_|gho_|github_pat_|AKIA[0-9A-Z]{16}|xox[baprs]-|glpat-|npm_[A-Za-z0-9]{30})' \
  "APIトークンを含まない"

# 除外つきの検査は assert_no_match では書けないので個別に組む。
check_with_exclusions() {
  local desc="$1" hits="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -z "$hits" ]; then
    _pass "$desc"
  else
    _fail "$desc" "$(printf '%s' "$hits" | head -5)"
  fi
}

# ユーザー名を含む絶対パス。テスト用のダミー /Users/someone だけ許す。
check_with_exclusions "ユーザー名を含む絶対パスを含まない" \
  "$(git grep -nIiE --untracked --exclude-standard '/Users/[a-z]' -- . 2>/dev/null | exclude_self \
     | grep -v '/Users/someone' || true)"

# op:// の実パスは data 経由でのみ書く。テンプレート変数と、
# 例示用のプレースホルダ op://Vault/... だけ許す。
check_with_exclusions "1Passwordの実パスを直書きしない" \
  "$(git grep -nIiE --untracked --exclude-standard 'op://[A-Za-z]' -- . 2>/dev/null | exclude_self \
     | grep -v '{{' | grep -v 'op://Vault/' || true)"

# --- 第2層: 語で検出する ---

words=""
if command -v chezmoi >/dev/null 2>&1; then
  words="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    '{{ range ((index ((index . "private") | default dict) "forbiddenWords") | default (list)) }}{{ . }}
{{ end }}' 2>/dev/null || true)"
fi

if [ -z "$(printf '%s' "$words" | tr -d '[:space:]')" ]; then
  printf '  skip: 禁止語リストが無いため第2層をスキップした（chezmoi data 未設定）\n'
else
  while IFS= read -r w; do
    [ -n "$w" ] || continue
    assert_no_match "$w" "禁止語を含まない: $(printf '%s' "$w" | cut -c1-2)…"
  done <<EOF
$words
EOF
fi

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
