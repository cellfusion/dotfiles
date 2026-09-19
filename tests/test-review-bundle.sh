#!/usr/bin/env bash
# review-bundle が組み立てる review package の header・範囲・mode を、実際の git
# リポジトリに対して確かめる。レビュー役は範囲を自分で調べられないので、header の
# sha が正しいことがレビュー範囲を照合する唯一の手掛かりになる。
set -u
. "$(dirname "$0")/lib/assert.sh"

BUNDLE="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_review-bundle"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo"
mkdir -p "$REPO"
git -c init.defaultBranch=main -C "$REPO" init --quiet
git -C "$REPO" config user.email tester@example.com
git -C "$REPO" config user.name tester
git -C "$REPO" config commit.gpgsign false
printf 'one\n' > "$REPO/a.txt"
git -C "$REPO" add a.txt
git -C "$REPO" commit --quiet -m 'chore: add a'
BASE_SHA="$(git -C "$REPO" rev-parse HEAD)"
printf 'two\n' > "$REPO/b.txt"
git -C "$REPO" add b.txt
git -C "$REPO" commit --quiet -m 'feat: add b'
MID_SHA="$(git -C "$REPO" rev-parse HEAD)"
printf 'three\n' > "$REPO/c.txt"
git -C "$REPO" add c.txt
git -C "$REPO" commit --quiet -m 'feat: add c'
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"

OUT="$TMP/out/review-package.diff"
out="$(bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" --out "$OUT" 2>&1)"
assert_eq "$?" "0" "review bundle: 祖先関係のある範囲を受理する"
assert_eq "$out" "$OUT" "review bundle: stdout へ出力先の絶対パスだけを書く"

header="$(head -n 1 "$OUT")"
assert_eq "$header" "# Review package: $BASE_SHA..$HEAD_SHA" \
  "review bundle: header の 1 行目を 40 桁の sha 2 つにする"
assert_eq "$(printf '%s' "$header" | grep -cE '^# Review package: [0-9a-f]{40}\.\.[0-9a-f]{40}$')" "1" \
  "review bundle: header が 40 桁の sha の書式に一致する"

body="$(cat "$OUT")"
assert_contains "$body" "## Commits" "review bundle: Commits の節を書く"
assert_contains "$body" "## Files changed" "review bundle: Files changed の節を書く"
assert_contains "$body" "## Diff" "review bundle: Diff の節を書く"
assert_contains "$body" "feat: add b" "review bundle: 範囲の途中の commit も Commits に出す"
assert_contains "$body" "feat: add c" "review bundle: 範囲の末尾の commit も Commits に出す"
assert_not_contains "$body" "chore: add a" "review bundle: base 自身の commit を範囲に含めない"
assert_eq "$(stat -f '%Lp' "$OUT")" "600" "review bundle: 出力を mode 0600 で書く"
assert_eq "$(stat -f '%Lp' "$TMP/out")" "700" "review bundle: 親ディレクトリを mode 0700 で作る"

mkdir -p "$TMP/preexisting"
chmod 755 "$TMP/preexisting"
bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" \
  --out "$TMP/preexisting/review-package.diff" >/dev/null 2>&1
assert_eq "$?" "0" "review bundle: 既にある親ディレクトリへも書ける"
assert_eq "$(stat -f '%Lp' "$TMP/preexisting")" "755" \
  "review bundle: 既にある親ディレクトリの mode を書き換えない"
assert_eq "$(stat -f '%Lp' "$TMP/preexisting/review-package.diff")" "600" \
  "review bundle: 既にある親ディレクトリへ書いた出力も mode 0600 にする"

bash "$BUNDLE" --cwd "$REPO" --base "$HEAD_SHA" --head "$BASE_SHA" \
  --out "$TMP/out/reversed.diff" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: base が head の祖先でない範囲を拒否する"

bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" --out "$OUT" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: --force 無しで既存の --out を上書きしない"
assert_contains "$(cat "$OUT")" "feat: add c" "review bundle: 拒否した呼び出しが既存の内容を壊さない"

bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head "$MID_SHA" --out "$OUT" --force >/dev/null 2>&1
assert_eq "$?" "0" "review bundle: --force で既存の --out を上書きする"
assert_eq "$(head -n 1 "$OUT")" "# Review package: $BASE_SHA..$MID_SHA" \
  "review bundle: --force の上書きが新しい範囲の header を書く"
assert_eq "$(stat -f '%Lp' "$OUT")" "600" "review bundle: --force の上書き後も mode 0600 を保つ"

bash "$BUNDLE" --cwd "$REPO" --base HEAD --head "$HEAD_SHA" --out "$TMP/out/symbolic.diff" >/dev/null 2>&1
assert_eq "$?" "0" "review bundle: symbolic ref を 40 桁の sha へ解決する"
assert_eq "$(head -n 1 "$TMP/out/symbolic.diff")" "# Review package: $HEAD_SHA..$HEAD_SHA" \
  "review bundle: header に symbolic ref を残さない"

bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head no-such-revision \
  --out "$TMP/out/missing.diff" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: 解決できない revision を拒否する"

bash "$BUNDLE" --cwd "$TMP" --base "$BASE_SHA" --head "$HEAD_SHA" \
  --out "$TMP/out/not-a-repo.diff" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: git リポジトリでない --cwd を拒否する"

bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --head "$HEAD_SHA" \
  --out "relative/out.diff" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: 相対パスの --out を拒否する"

bash "$BUNDLE" --cwd "$REPO" --base "$BASE_SHA" --out "$TMP/out/no-head.diff" >/dev/null 2>&1
assert_eq "$?" "2" "review bundle: --head の無い呼び出しを拒否する"

assert_summary
