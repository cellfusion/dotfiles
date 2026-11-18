#!/usr/bin/env bash
# Check both distributed runtime variants of the Timeline planning instructions.
set -eu
. "$(dirname "$0")/lib/assert.sh"

for tool in codex claude; do
  for skill in writing-plans executing-plans multi-agent-development; do
    rendered="$(render_template "agent-skills/$skill/SKILL.md" "$tool")"
    assert_contains "$rendered" 'moi-companion timeline --help' "$tool/$skill uses installed contract"
    assert_contains "$rendered" 'moi-companion timeline invoke --stdin' "$tool/$skill uses stdin"
    assert_contains "$rendered" 'UUID' "$tool/$skill identifies plan"
    assert_contains "$rendered" 'revision' "$tool/$skill protects concurrent updates"
    assert_contains "$rendered" 'terminal output' "$tool/$skill excludes sensitive output"
    assert_contains "$rendered" 'agent execution host' "$tool/$skill defaults to agent host"
    assert_contains "$rendered" 'same effective OS user as the agent process' "$tool/$skill uses agent process identity"
    assert_contains "$rendered" 'handed-off host/user' "$tool/$skill retains handed-off target"
    assert_contains "$rendered" 'preserve the existing plan identity' "$tool/$skill preserves existing identity"
    assert_contains "$rendered" 'without authorization' "$tool/$skill forbids unauthorized connection"
    assert_contains "$rendered" 'do not create a replacement plan' "$tool/$skill forbids replacement plan"
    assert_contains "$rendered" 'parent or user' "$tool/$skill coordinates safe updates"
    assert_contains "$rendered" 'remote UI client' "$tool/$skill excludes client host"
    assert_contains "$rendered" 'normally no confirmation question' "$tool/$skill avoids needless questions"
    assert_contains "$rendered" 'explicitly requests another host' "$tool/$skill respects explicit host"
    assert_contains "$rendered" 'never substitute the current host' "$tool/$skill avoids host substitution"
    assert_contains "$rendered" 'connection and authorization' "$tool/$skill checks remote permission"
    assert_contains "$rendered" 'host cannot be identified' "$tool/$skill handles unknown host"
  done
done
for tool in codex claude; do
  writing="$(render_template agent-skills/writing-plans/SKILL.md "$tool")"
  assert_contains "$writing" 'trusted record or parent handoff' "$tool existing handoff is selected"
  assert_contains "$writing" 'confirm the intended task mapping' "$tool confirms existing task mapping"
  assert_contains "$writing" 'do not automatically append tasks' "$tool avoids unconditional task append"
  assert_contains "$writing" 'no applicable record exists' "$tool creates only when no record applies"
  assert_contains "$writing" 'whether to create a new one' "$tool asks when existence is unknown"
  assert_contains "$writing" 'do not guess a link to an old record' "$tool avoids speculative links"
  assert_contains "$writing" 'parent IDs' "$tool task hierarchy is registered"
  assert_contains "$writing" 'absolute plan path' "$tool external plan is handed off"
done
for skill in executing-plans multi-agent-development; do
  rendered="$(render_template "agent-skills/$skill/SKILL.md" codex)"
  assert_contains "$rendered" 'Timeline plan by UUID' "$skill reads Timeline identity"
  assert_contains "$rendered" 'if it is confirmed' "$skill distinguishes confirmed unregistered plans"
  assert_contains "$rendered" 'whether to create' "$skill asks when record existence is unknown"
  assert_contains "$rendered" 'do not infer by name or create a duplicate' "$skill avoids duplicate records"
done
multi="$(render_template agent-skills/multi-agent-development/SKILL.md codex)"
assert_contains "$multi" 'parent is accountable' 'parent owns parallel updates'
assert_summary
