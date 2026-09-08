#!/usr/bin/env bash
# sdd-workspace が agent-docs-dir の下に workspace を作り、
# review-package と task-brief の既定の出力先がその下になることを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SDD="$CHEZMOI_SOURCE/private_dot_agents/skills/subagent-driven-development/scripts"
SHARED="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 配布後のレイアウトを再現する。sdd-workspace は ../../_shared/scripts を見る。
mkdir -p "$TMP/skills/subagent-driven-development/scripts" "$TMP/skills/_shared/scripts"
for s in sdd-workspace review-package task-brief; do
  cp "$SDD/executable_$s" "$TMP/skills/subagent-driven-development/scripts/$s"
  chmod +x "$TMP/skills/subagent-driven-development/scripts/$s"
done
cp "$SHARED/executable_agent-docs-dir" "$TMP/skills/_shared/scripts/agent-docs-dir"
chmod +x "$TMP/skills/_shared/scripts/agent-docs-dir"
SCRIPTS="$TMP/skills/subagent-driven-development/scripts"

# remote を持たないリポジトリ。agent-docs-dir は段 2 で末尾 2 要素を使う。
repo="$TMP/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
cat > "$repo/2026-09-08-thing.md" <<'PLAN'
# プラン

### Task 1: 何かを作る

**Files:**
- Create: `a.txt`
PLAN
printf 'a\n' > "$repo/a.txt"
git -C "$repo" add -A
git -C "$repo" commit -qm 'first'
base="$(git -C "$repo" rev-parse HEAD)"
printf 'b\n' >> "$repo/a.txt"
git -C "$repo" commit -qam 'second'

SLUG="$(basename "$TMP")/repo"
plan="$repo/2026-09-08-thing.md"

ws="$(cd "$repo" && AGENT_DOCS_ROOT="$TMP/docs" bash "$SCRIPTS/sdd-workspace" "$plan")"
assert_eq "$ws" "$TMP/docs/$SLUG/sdd/2026-09-08-thing" \
  "workspace を agent-docs-dir の下のプラン名のディレクトリにする"
assert_eq "$([ -d "$ws" ] && echo yes || echo no)" "yes" "workspace を作る"

# 同じリポジトリのサブディレクトリから呼んでも同じパスになる。
mkdir -p "$repo/sub"
ws2="$(cd "$repo/sub" && AGENT_DOCS_ROOT="$TMP/docs" bash "$SCRIPTS/sdd-workspace" "$plan")"
assert_eq "$ws2" "$ws" "呼び出し位置が変わっても同じ workspace を返す"

# task-brief は OUTFILE 省略時に workspace の下へ書く。
(cd "$repo" && AGENT_DOCS_ROOT="$TMP/docs" bash "$SCRIPTS/task-brief" "$plan" 1) >/dev/null
assert_eq "$([ -f "$ws/task-1-brief.md" ] && echo yes || echo no)" \
          "yes" "task-brief の既定の出力先が workspace の下になる"

# review-package も OUTFILE 省略時に workspace の下へ書く。
(cd "$repo" && AGENT_DOCS_ROOT="$TMP/docs" \
  bash "$SCRIPTS/review-package" "$plan" "$base" HEAD) >/dev/null
assert_eq "$(find "$ws" -name 'review-*.diff' | wc -l | tr -d ' ')" "1" \
  "review-package の既定の出力先が workspace の下になる"

# 旧経路の痕跡が残っていない。
src="$(cat "$SDD/executable_sdd-workspace")"
assert_contains "$src" "agent-docs-dir" "sdd-workspace が agent-docs-dir を呼ぶ"
assert_not_contains "$src" "cellfusion-workdir" "sdd-workspace が旧スクリプトを呼ばない"
assert_not_contains "$src" "_cellfusion" "sdd-workspace が旧保存先を書かない"
assert_not_contains "$(cat "$SDD/executable_review-package")" "_cellfusion" \
  "review-package のコメントが旧保存先を書かない"
assert_not_contains "$(cat "$SDD/executable_task-brief")" "_cellfusion" \
  "task-brief のコメントが旧保存先を書かない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
