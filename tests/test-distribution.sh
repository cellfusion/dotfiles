#!/usr/bin/env bash
# Task 4 の plan-auditor と task-brief の配布対象を検証する。
set -u

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  printf '  ok: %s\n' "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$1" >&2
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) pass "$3" ;;
    *) fail "$3 (missing: $2)" ;;
  esac
}

root="$(cd "$(dirname "$0")/.." && pwd)"
managed="$(chezmoi managed --source "$root" 2>/dev/null || true)"

assert_contains "$managed" '.agents/agent-defs/prompts/plan-auditor.md' \
  'plan-auditor prompt を配る'
assert_contains "$managed" '.agents/agent-defs/schemas/plan-auditor.json' \
  'plan-auditor schema を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/task-brief' \
  'task-brief を配る'
assert_contains "$managed" '.agents/skills/task-routing/SKILL.md' \
  'distribute task-routing skill'
assert_contains "$managed" '.config/claude/skills/task-routing/SKILL.md' \
  'distribute Claude task-routing skill'
assert_contains "$managed" '.config/opencode/skills/task-routing/SKILL.md' \
  'distribute OpenCode task-routing skill'
assert_contains "$managed" '.agents/agent-defs/prompts/intake-router.md' \
  'distribute intake-router prompt'
assert_contains "$managed" '.agents/agent-defs/schemas/intake-router.json' \
  'distribute intake-router schema'
assert_contains "$managed" '.config/claude/agents/intake-router.md' \
  'distribute Claude intake-router agent'
assert_contains "$managed" '.config/opencode/agents/intake-router.md' \
  'distribute OpenCode intake-router agent'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-worktree' \
  'mad-worktree を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-progress' \
  'mad-progress を配る'

for role in implementer task-reviewer re-reviewer final-reviewer; do
  assert_contains "$managed" ".agents/agent-defs/prompts/$role.md" \
    "MAD delivery role: prompts/$role.md を配る"
  assert_contains "$managed" ".agents/agent-defs/schemas/$role.json" \
    "MAD delivery role: schemas/$role.json を配る"
done
assert_contains "$managed" '.agents/agent-defs/prompts/architectural-implementer.md' \
  'architectural implementer prompt を配る'
assert_contains "$managed" '.agents/agent-defs/schemas/architectural-implementer.json' \
  'architectural implementer schema を配る'
assert_contains "$managed" '.config/claude/agents/architectural-implementer.md' \
  'Claude architectural implementer agent を配る'
assert_contains "$managed" '.config/opencode/agents/architectural-implementer.md' \
  'OpenCode architectural implementer agent を配る'
assert_contains "$managed" '.agents/agent-defs/prompts/escalation-judge.md' \
  'escalation judge prompt を配る'
assert_contains "$managed" '.agents/agent-defs/schemas/escalation-judge.json' \
  'escalation judge schema を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/escalation-policy' \
  'escalation policy script を配る'
assert_contains "$managed" '.agents/skills/task-routing/scripts/single-implementer' \
  'single implementer script を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/paseo-cli-adapter' \
  'paseo CLI adapter を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-outcome-record' \
  'mad outcome recorder を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-outcome-import' \
  'mad outcome importer を配る'
assert_contains "$managed" '.agents/skills/task-routing/scripts/mad-route-admit' \
  'mad route admission を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-route-record' \
  'mad route recorder を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-route-summary' \
  'mad route summary を配る'
assert_contains "$managed" '.local/share/agent-config/mad-route.js' \
  'mad route contract を配る'
assert_contains "$managed" '.agents/skills/multi-agent-development/scripts/mad-escalation-controller' \
  'mad escalation controller を配る'
assert_contains "$managed" '.local/share/agent-config/mad-outcome.js' \
  'mad outcome contract を配る'
assert_contains "$managed" '.config/claude/agents/escalation-judge.md' \
  'Claude escalation judge agent を配る'
assert_contains "$managed" '.config/opencode/agents/escalation-judge.md' \
  'OpenCode escalation judge agent を配る'

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
