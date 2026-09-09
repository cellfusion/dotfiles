#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"
SCRIPT="$CHEZMOI_SOURCE/private_dot_local/bin/executable_agent-docs-migrate"
DOCS_DIR_BIN="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_agent-docs-dir"
TMP="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT

# 事例ごとに git リポジトリと保存先の根を作る。remote を持たないので、
# agent-docs-dir はチェックアウトのパスの末尾 2 要素を slug に使う。
new_case() {
  local repo="$TMP/$1/cellfusion/dotfiles"
  mkdir -p "$repo" "$TMP/$1-docs"
  git -C "$repo" init -q
  printf '%s\n' "$repo"
}

run() {
  local root="$1"
  shift
  AGENT_DOCS_ROOT="$root" AGENT_DOCS_DIR_BIN="$DOCS_DIR_BIN" bash "$SCRIPT" "$@"
}

exists() { [ -e "$1" ] && echo yes || echo no; }

# --- dry-run は既定で、ファイルを動かさない ---
repo="$(new_case dryrun)"
mkdir -p "$repo/_cellfusion/plans"
printf 'a\n' > "$repo/_cellfusion/plans/a.md"
out="$(run "$TMP/dryrun-docs" "$repo")"
status=$?
assert_eq "$status" "0" "dry-run の終了ステータス"
assert_contains "$out" "dry-run" "dry-run と分かる出力を出す"
assert_eq "$(exists "$repo/_cellfusion/plans/a.md")" "yes" "dry-run は移行元を残す"
assert_eq "$(exists "$TMP/dryrun-docs/cellfusion/dotfiles/plans/a.md")" "no" \
  "dry-run は移行先に書かない"

# --- --apply は直下のエントリを名前を変えずに移す ---
repo="$(new_case apply)"
mkdir -p "$repo/_cellfusion/plans" "$repo/_cellfusion/drafts"
printf 'a\n' > "$repo/_cellfusion/plans/a.md"
printf 'b\n' > "$repo/_cellfusion/drafts/b.md"
printf 'c\n' > "$repo/_cellfusion/top.md"
printf '*\n' > "$repo/_cellfusion/.gitignore"
dest="$TMP/apply-docs/cellfusion/dotfiles"
out="$(run "$TMP/apply-docs" --apply "$repo")"
assert_eq "$(exists "$dest/plans/a.md")" "yes" "レイアウト表にあるディレクトリを移す"
assert_eq "$(exists "$dest/drafts/b.md")" "yes" "レイアウト表に無いディレクトリも移す"
assert_eq "$(exists "$dest/top.md")" "yes" "直下のファイルを移す"
assert_eq "$(exists "$dest/.gitignore")" "no" "自己無視の .gitignore は移さない"
assert_eq "$(exists "$repo/_cellfusion")" "no" "空になった _cellfusion を消す"

# --- 同名で中身が一致すれば移行元を消す ---
repo="$(new_case same)"
dest="$TMP/same-docs/cellfusion/dotfiles"
mkdir -p "$repo/_cellfusion/plans" "$dest/plans"
printf 'same\n' > "$repo/_cellfusion/plans/a.md"
printf 'same\n' > "$dest/plans/a.md"
out="$(run "$TMP/same-docs" --apply "$repo")"
assert_eq "$(exists "$repo/_cellfusion")" "no" "一致した後に _cellfusion を消す"
assert_eq "$(cat "$dest/plans/a.md")" "same" "移行先の中身を変えない"

# --- 同名で中身が違えば移行元に残して報告する ---
repo="$(new_case diff)"
dest="$TMP/diff-docs/cellfusion/dotfiles"
mkdir -p "$repo/_cellfusion/plans" "$dest/plans"
printf 'new\n' > "$repo/_cellfusion/plans/a.md"
printf 'old\n' > "$dest/plans/a.md"
out="$(run "$TMP/diff-docs" --apply "$repo")"
assert_eq "$(exists "$repo/_cellfusion/plans/a.md")" "yes" "中身が違う移行元を残す"
assert_eq "$(cat "$dest/plans/a.md")" "old" "中身が違うとき移行先を上書きしない"
assert_contains "$out" "$repo/_cellfusion/plans/a.md" "残した移行元のパスを出す"
assert_eq "$(exists "$repo/_cellfusion")" "yes" "残留があれば _cellfusion を消さない"

# --- _cellfusion が無いリポジトリでは何もしない ---
repo="$(new_case none)"
out="$(run "$TMP/none-docs" --apply "$repo")"
status=$?
assert_eq "$status" "0" "_cellfusion が無いときの終了ステータス"
assert_eq "$(exists "$TMP/none-docs/cellfusion")" "no" "_cellfusion が無いとき保存先を作らない"

# --- 中身が無い _cellfusion は消す ---
repo="$(new_case empty)"
mkdir -p "$repo/_cellfusion"
printf '*\n' > "$repo/_cellfusion/.gitignore"
out="$(run "$TMP/empty-docs" --apply "$repo")"
assert_eq "$(exists "$repo/_cellfusion")" "no" "中身が無い _cellfusion を消す"

# --- 通常ファイルでないエントリは移さず、消しもしない ---
repo="$(new_case symlink)"
mkdir -p "$repo/_cellfusion/plans"
printf 'a\n' > "$repo/_cellfusion/plans/a.md"
printf 'outside\n' > "$TMP/symlink-outside.md"
ln -s "$TMP/symlink-outside.md" "$repo/_cellfusion/link.md"
out="$(run "$TMP/symlink-docs" --apply "$repo")"
assert_eq "$(exists "$TMP/symlink-docs/cellfusion/dotfiles/plans/a.md")" "yes" \
  "通常ファイルは移す"
assert_eq "$(exists "$repo/_cellfusion/link.md")" "yes" "symlink を消さない"
assert_eq "$(exists "$repo/_cellfusion")" "yes" "symlink が残れば _cellfusion を消さない"
assert_contains "$out" "$repo/_cellfusion" "残った _cellfusion のパスを出す"

# --- 引数を省くと現在の作業ディレクトリを対象にする ---
repo="$(new_case cwd)"
mkdir -p "$repo/_cellfusion/specs"
printf 's\n' > "$repo/_cellfusion/specs/s.md"
out="$(cd "$repo" && run "$TMP/cwd-docs" --apply)"
assert_eq "$(exists "$TMP/cwd-docs/cellfusion/dotfiles/specs/s.md")" "yes" \
  "引数を省くと現在の作業ディレクトリを使う"

# --- git リポジトリの外では失敗する ---
mkdir -p "$TMP/notrepo"
out="$(run "$TMP/notrepo-docs" --apply "$TMP/notrepo" 2>"$TMP/notrepo.err")"
status=$?
assert_eq "$status" "1" "git リポジトリの外では失敗する"
assert_contains "$(cat "$TMP/notrepo.err")" "git" "git リポジトリの外の標準エラー"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
