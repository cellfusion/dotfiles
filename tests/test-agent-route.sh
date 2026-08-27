#!/usr/bin/env bash
# agent-route が役割からエンジンとモデルを解決することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

ROUTE="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_agent-route"

# テンプレートを展開したアセットを一時ディレクトリに作る。
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
for f in routing manifests tiers; do
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/$f.json\" . }}" > "$FIXTURE/$f.json"
done

route() { AGENT_DEFS_DIR="$FIXTURE" node "$ROUTE" "$@"; }

out="$(route sdd-implementer)"
assert_contains "$out" "engine=codex" "implementer: 既定は codex"
assert_contains "$out" "model=gpt-5.6-luna" "implementer: work/codex は luna"
assert_contains "$out" "effort=high" "implementer: effort は high"
assert_contains "$out" "access=write" "implementer: 書き込み可"
assert_contains "$out" "sandbox=workspace-write" "implementer: sandbox は workspace-write"

out="$(route sdd-task-reviewer)"
assert_contains "$out" "engine=claude" "task-reviewer: claude"
assert_contains "$out" "model=sonnet" "task-reviewer: work/claude は sonnet"
assert_contains "$out" "sandbox=read-only" "task-reviewer: 読み取り専用"

out="$(route sdd-implementer-think)"
assert_contains "$out" "engine=claude" "implementer-think: 既定は claude"
assert_contains "$out" "model=opus" "implementer-think: think/claude は opus"

# engine を差し替えると model も追随する。
node -e '
const fs = require("node:fs"), p = process.argv[1]
const d = JSON.parse(fs.readFileSync(p, "utf8"))
d["sdd-implementer"].engine = "claude"
fs.writeFileSync(p, JSON.stringify(d))
' "$FIXTURE/routing.json"
out="$(route sdd-implementer)"
assert_contains "$out" "engine=claude" "engine を claude にすると claude になる"
assert_contains "$out" "model=sonnet" "engine を claude にすると sonnet になる"

# tier 上書きが効く。
node -e '
const fs = require("node:fs"), p = process.argv[1]
const d = JSON.parse(fs.readFileSync(p, "utf8"))
d["sdd-implementer"] = { engine: "codex", tier: "think" }
fs.writeFileSync(p, JSON.stringify(d))
' "$FIXTURE/routing.json"
out="$(route sdd-implementer)"
assert_contains "$out" "model=gpt-5.6-terra" "tier 上書きで terra になる"

# 未知の役割はエラーで落ちる。
if route no-such-role >/dev/null 2>&1; then
  _fail "未知の役割はエラーになる" "終了ステータスが 0 だった"
  TESTS_RUN=$((TESTS_RUN + 1))
else
  TESTS_RUN=$((TESTS_RUN + 1))
  _pass "未知の役割はエラーになる"
fi

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
