#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# 3 ツールぶんの runtime ブロックが、論理名 6 つすべてを説明していること。
for tool in claude codex opencode; do
  out="$(render_template "agent-skills/_runtime/$tool.md" "$tool")"
  for name in '[ask-user]' '[dispatch-subagent' '[resume-subagent]' \
              '[deterministic-loop]' '[todo]' '[web-search]'; do
    assert_contains "$out" "$name" "$tool: $name の行がある"
  done
done

# Claude 版だけが実ツール名を持つ。
claude_out="$(render_template "agent-skills/_runtime/claude.md" "claude")"
assert_contains "$claude_out" "AskUserQuestion" "claude: AskUserQuestion を指す"
assert_contains "$claude_out" "Workflow" "claude: Workflow を指す"
assert_contains "$claude_out" "SendMessage" "claude: SendMessage を指す"

# Codex / opencode 版は Claude 専用ツールの名前を出さない。
for tool in codex opencode; do
  out="$(render_template "agent-skills/_runtime/$tool.md" "$tool")"
  assert_not_contains "$out" "AskUserQuestion" "$tool: AskUserQuestion を出さない"
  assert_not_contains "$out" "SendMessage" "$tool: SendMessage を出さない"
  assert_contains "$out" "利用不可" "$tool: deterministic-loop を利用不可と伝える"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
