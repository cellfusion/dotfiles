#!/usr/bin/env bash
# agent-skills の退役名と、各エージェントへの共通 worktree ルールの配布を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

matches="$(rg -ni 'sdd|subagent-driven-development' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills" || true)"
assert_eq "$matches" "" \
  'agent-skills: SDD と subagent-driven-development の参照を残さない'

# 各 CLI が読むファイルに本文を展開し、import 対応の違いに依存しない。
workflow="$(render_template 'agent-instructions/worktree-workflow.md' codex)"
for target in \
  .pi/agent/AGENTS.md \
  .config/claude/CLAUDE.md \
  .config/codex/AGENTS.md \
  .agents/AGENTS.md \
  .config/opencode/AGENTS.md \
  .codex/AGENTS.md
do
  rendered="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/$target")"
  assert_eq "$?" "0" "$target: chezmoi で展開できる"
  assert_contains "$rendered" "$workflow" "$target: 共通 worktree 本文を含む"
  for rule in \
    '## Documentation Format Preferences' \
    'Prefer text-based diagram formats such as Mermaid' \
    'Prefer Markdown tables' \
    'Do not make excuses or justify your own mistakes.' \
    '## Explaining Work to the User' \
    '## Deliver the requested implementation' \
    'Format the owned changes before committing'
  do
    assert_contains "$rendered" "$rule" "$target: 共通指示 $rule を含む"
  done
  assert_eq "$(printf '%s\n' "$rendered" | grep -c '^## Documentation Format Preferences$')" \
    "1" "$target: 文書形式の共通指示を重複させない"
  assert_eq "$(printf '%s\n' "$rendered" | grep -c '^## Worktree-based Git workflow$')" \
    "1" "$target: ルールを重複させない"
done

assert_contains "$workflow" 'git merge --no-ff' 'worktree: merge commit 方針を保持する'
assert_contains "$workflow" 'coherent changes on that branch' 'worktree: 作業ブランチで意味のある単位を commit する'
assert_contains "$workflow" 'do not substitute copying their files directly' 'worktree: snapshot のコピーで merge を置き換えない'

pi="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/.pi/agent/AGENTS.md")"
for heading in \
  '## Project to-do lists (Herdr)' \
  '## Explaining Work to the User' \
  '## Deliver the requested implementation'
do
  assert_contains "$pi" "$heading" "Pi: 既存メモリ $heading を保持する"
done
codex="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/.codex/AGENTS.md")"
assert_contains "$codex" '<!-- over9k:todo -->' '直接起動 Codex: 既存 TODO 指示を保持する'

claude_link="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/.claude/CLAUDE.md")"
assert_eq "$claude_link" "$HOME/.config/claude/CLAUDE.md" '直接起動 Claude: 管理中の共通指示へリンクする'
for target in .codex/AGENTS.md .config/opencode/AGENTS.md; do
  assert_eq "$(grep -Fxc "$target" "$CHEZMOI_SOURCE/.chezmoiremove" || true)" \
    "0" "$target: 旧削除指定と競合しない"
done

assert_summary
