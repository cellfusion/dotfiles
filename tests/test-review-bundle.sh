#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"
bundle="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_review-bundle"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name Test
printf 'original\n' > "$repo/tracked file"
printf 'remove me\n' > "$repo/deleted"
printf 'untouched\n' > "$repo/outside"
printf 'rename origin\n' > "$repo/old name"
printf 'unselected parent content\n' > "$repo/parent"
git -C "$repo" add .
git -C "$repo" commit -qm base
base="$(git -C "$repo" rev-parse HEAD)"
printf 'committed\n' > "$repo/tracked file"
git -C "$repo" commit -qam change
head="$(git -C "$repo" rev-parse HEAD)"
status=0
bash "$bundle" --cwd "$repo" --base "$base" --head "$head" --out "$tmp/commit" >/dev/null || status=$?
assert_eq "$status" 0 'commit package succeeds'
mv "$repo/old name" "$repo/new name"
assert_contains "$(cat "$tmp/commit")" "$base..$head" 'commit identity remains unchanged'
printf 'staged\n' > "$repo/tracked file"
git -C "$repo" add 'tracked file'
printf 'final unstaged\n' >> "$repo/tracked file"
rm "$repo/deleted"
printf 'untracked content\n' > "$repo/new file"
printf '#!/bin/sh\n' > "$repo/executable"
chmod +x "$repo/executable"
ln -s 'new file' "$repo/link"
printf 'unrelated secret\n' > "$repo/outside"
printf '*.ignored\n' > "$repo/.gitignore"
printf 'ignored content\n' > "$repo/selected.ignored"
printf 'not selected\n' > "$repo/other.ignored"
printf '*.filtered filter=fixture\n' > "$repo/.gitattributes"
printf '#!/bin/sh\nprintf touched > "%s"\ncat\n' "$tmp/filter-ran" > "$tmp/filter"
chmod +x "$tmp/filter"
git -C "$repo" config filter.fixture.clean "$tmp/filter"
printf 'raw worktree bytes\n' > "$repo/payload.filtered"
printf '\000binary\001' > "$repo/binary"
before="$(git -C "$repo" status --porcelain=v1 -uall)"
index_before="$(git -C "$repo" diff --cached --binary)"
status=0
bash "$bundle" --cwd "$repo" --base "$base" --worktree --path 'tracked file' --path deleted --path 'new file' --path executable --path link --path selected.ignored --path binary --path payload.filtered --path 'old name' --path 'new name' --out "$tmp/worktree" >/dev/null || status=$?
assert_eq "$status" 0 'worktree package succeeds'
if [ -f "$tmp/worktree" ]; then
  content="$(cat "$tmp/worktree")"
  assert_contains "$content" 'Worktree snapshot' 'snapshot is not called a commit'
  assert_contains "$content" 'final unstaged' 'final unstaged state included'
  assert_contains "$content" 'untracked content' 'explicit untracked file included'
  assert_contains "$content" 'old name' 'rename old path included'
  assert_contains "$content" 'new name' 'rename new path included'
  assert_contains "$content" 'deleted file mode' 'deletion included'
  assert_contains "$content" 'new file mode 100755' 'executable mode included'
  assert_contains "$content" 'new file mode 120000' 'symlink included'
  assert_contains "$content" 'ignored content' 'explicit ignored file included'
  assert_contains "$content" 'GIT binary patch' 'binary patch included'
  assert_contains "$content" 'raw worktree bytes' 'snapshot includes raw worktree content'
  assert_not_contains "$content" 'unrelated secret' 'unselected tracked changes excluded'
  assert_not_contains "$content" 'not selected' 'unselected ignored file excluded'
else
  fail_check 'worktree package exists'
fi
if [ -e "$tmp/filter-ran" ]; then fail_check 'snapshot does not execute clean filters'; else pass 'snapshot does not execute clean filters'; fi
assert_eq "$(git -C "$repo" status --porcelain=v1 -uall)" "$before" 'worktree status preserved'
assert_eq "$(git -C "$repo" diff --cached --binary)" "$index_before" 'index preserved'
for args in '--worktree' '--worktree --head HEAD --path outside' '--worktree --path ../escape' '--worktree --path .' '--worktree --path nonexistent' '--worktree --path .git/config'; do
  # Arguments here intentionally contain no spaces.
  if bash "$bundle" --cwd "$repo" --base "$base" $args --out "$tmp/failure" >/dev/null 2>&1; then
    fail_check "rejects invalid arguments: $args"
  else
    pass "rejects invalid arguments: $args"
  fi
done
if bash "$bundle" --cwd "$repo" --base "$base" --worktree --path outside --out "$repo/package" >/dev/null 2>&1; then
  fail_check 'rejects output inside repository'
else
  pass 'rejects output inside repository'
fi
mkdir "$tmp/bin"
real_git="$(command -v git)"
cat > "$tmp/bin/git" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = write-tree ] && [ ! -e "$REVIEW_RACE_MARKER" ]; then
    "$REVIEW_REAL_GIT" "$@"
    result=$?
    printf 'concurrent edit\n' >> "$REVIEW_RACE_FILE"
    : > "$REVIEW_RACE_MARKER"
    exit "$result"
  fi
done
exec "$REVIEW_REAL_GIT" "$@"
EOF
chmod +x "$tmp/bin/git"
export REVIEW_REAL_GIT="$real_git" REVIEW_RACE_FILE="$repo/tracked file" REVIEW_RACE_MARKER="$tmp/raced"
if PATH="$tmp/bin:$PATH" bash "$bundle" --cwd "$repo" --base "$base" --worktree --path 'tracked file' --out "$tmp/race" >/dev/null 2>&1; then
  fail_check 'rejects concurrent modification'
else
  pass 'rejects concurrent modification'
fi
if [ -e "$tmp/race" ]; then fail_check 'race does not publish package'; else pass 'race does not publish package'; fi
rm "$repo/parent"
mkdir "$repo/parent"
printf 'selected child\n' > "$repo/parent/child"
if bash "$bundle" --cwd "$repo" --base "$base" --worktree --path parent/child --out "$tmp/tree-conflict" >/dev/null 2>&1; then
  fail_check 'rejects implicit unselected parent deletion'
else
  pass 'rejects implicit unselected parent deletion'
fi
mkdir "$repo/dir"
ln -s "$tmp" "$repo/dir/escape"
if bash "$bundle" --cwd "$repo" --base "$base" --worktree --path dir/escape/file --out "$tmp/failure" >/dev/null 2>&1; then
  fail_check 'rejects symlink ancestor'
else
  pass 'rejects symlink ancestor'
fi
assert_summary
