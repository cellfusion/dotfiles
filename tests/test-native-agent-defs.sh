#!/usr/bin/env bash
# Claude Code / Codex の native role 定義が同じ catalog から配布されることを検証する。
set -u

source "$(dirname "$0")/lib/assert.sh"

roles=(
  implementer
  task-reviewer
  plan-auditor
  intake-router
  architectural-implementer
  escalation-judge
  re-reviewer
  final-reviewer
  spec-author
  plan-author
  synthesizer
  reviewer
  researcher
  review-synthesizer
)

for role in "${roles[@]}"; do
  [ -f "$CHEZMOI_SOURCE/private_dot_config/claude/agents/$role.md.tmpl" ] && \
    _pass "Claude native agent source exists: $role" || \
    _fail "Claude native agent source exists: $role"
  [ -f "$CHEZMOI_SOURCE/private_dot_config/codex/agents/$role.toml.tmpl" ] && \
    _pass "Codex native agent source exists: $role" || \
    _fail "Codex native agent source exists: $role"
done

claude="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "private_dot_config/claude/agents/researcher.md.tmpl" . }}' 2>/dev/null || true)"
assert_contains "$claude" 'name: researcher' 'Claude wrapper has role name'
assert_contains "$claude" 'tools: Read, Grep, Glob' 'Claude read role has read-only tools'
assert_contains "$claude" 'あなたは調査役である。' 'Claude wrapper includes canonical prompt'

codex="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "private_dot_config/codex/agents/researcher.toml.tmpl" . }}' 2>/dev/null || true)"
assert_contains "$codex" 'name = "researcher"' 'Codex role file has role name'
assert_contains "$codex" 'developer_instructions = """' 'Codex role file has developer instructions'
assert_contains "$codex" 'あなたは調査役である。' 'Codex role file includes canonical prompt'

assert_summary
