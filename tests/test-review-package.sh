#!/usr/bin/env bash
# review-package が書く header の範囲表記を検証する。
#
# header の base と head は、レビュアーがそのまま status に写して返し、controller が
# 期待した範囲と照合する。ここに HEAD のような symbolic ref を残すと、Bash を持たない
# レビュアー（tools は Read,Grep,Glob,Write）には sha へ解決できず、照合が必ず失敗する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts/executable_review-package"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
printf 'plan\n' > "$repo/plan.md"
printf 'a\n' > "$repo/a.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm 'first'
base="$(git -C "$repo" rev-parse HEAD)"
printf 'b\n' >> "$repo/a.txt"
git -C "$repo" commit -qam 'second'
head="$(git -C "$repo" rev-parse HEAD)"

pkg() {
  out="$TMP/pkg.diff"
  rm -f "$out"
  (cd "$repo" && bash "$SCRIPT" "$repo/plan.md" "$1" "$2" "$out") > "$TMP/stdout.txt" 2>&1 \
    || cat "$TMP/stdout.txt" >&2
  head -n 1 "$out" 2>/dev/null
}

# HEAD を渡しても header には解決済みの sha が入る。
first="$(pkg "$base" HEAD)"
assert_eq "$first" "# Review package: $base..$head" "header は解決済みの sha で範囲を書く"
assert_not_contains "$first" "HEAD" "header に symbolic ref を残さない"

# 短縮 sha を渡しても header は完全な sha になる。
first="$(pkg "$(git -C "$repo" rev-parse --short "$base")" HEAD)"
assert_eq "$first" "# Review package: $base..$head" "短縮 sha を渡しても header は完全な sha にする"

# diff の中身は従来どおり base..head の範囲である。
assert_contains "$(cat "$TMP/pkg.diff")" "second" "package には範囲内のコミットが入る"

# 解決できない ref は package を作らずに止める。sha への解決はここで一度だけ行うので、
# ここを素通りさせると範囲の分からない package がレビュアーに渡る。
(cd "$repo" && bash "$SCRIPT" "$repo/plan.md" nosuchref HEAD "$TMP/bad.diff") > "$TMP/bad.txt" 2>&1
rc=$?
assert_eq "$rc" "2" "解決できない BASE で止まる"
assert_contains "$(cat "$TMP/bad.txt")" "bad BASE" "止まった理由を出す"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
