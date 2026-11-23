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
assert_contains "$pi" 'When to use brainstorming' 'Pi: ブレストの判断基準を起動時に配布する'
assert_contains "$pi" '「案を比較したい」「方針を一緒に決めたい」' 'Pi: 比較・設計相談を発動対象にする'
assert_contains "$pi" 'Skip brainstorming for a settled local change' 'Pi: 明確な小変更は除外する'
assert_contains "$pi" 'A design-only request' 'Pi: 設計の相談と実装の許可を区別する'
codex="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/.codex/AGENTS.md")"
assert_contains "$codex" '<!-- over9k:todo -->' '直接起動 Codex: 既存 TODO 指示を保持する'

claude_link="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/.claude/CLAUDE.md")"
assert_eq "$claude_link" "$HOME/.config/claude/CLAUDE.md" '直接起動 Claude: 管理中の共通指示へリンクする'
for target in .codex/AGENTS.md .config/opencode/AGENTS.md; do
  assert_eq "$(grep -Fxc "$target" "$CHEZMOI_SOURCE/.chezmoiremove" || true)" \
    "0" "$target: 旧削除指定と競合しない"
done

# 会話内の調査が Vault 書き込みに切り替わらないよう、発動条件と本文の両方を確認する。
for base in .agents/skills .config/claude/skills; do
  research="$(chezmoi cat --source "$CHEZMOI_SOURCE" "$HOME/$base/research/SKILL.md")"
  assert_eq "$?" "0" "$base: research を展開できる"
  assert_contains "$research" '会話内で完結する調査や、実装・デバッグに必要な下調べには使わない' \
    "$base: 会話内の調査を自動発動条件から除外する"
  assert_contains "$research" 'スキル本文が読み込まれただけでは、Vault を作成・更新する理由にならない' \
    "$base: 本文の読み込みと保存指示を区別する"
done

# 履歴は合成データのみ。パスや生の記録を集計結果に含めない。
audit="$CHEZMOI_SOURCE/private_dot_local/bin/executable_agent-skill-audit"
fixture="$(mktemp -d)" || exit 1
trap 'rm -rf -- "$fixture"' EXIT
printf '%s\n' \
  '{"timestamp":"2026-11-11T23:30:00-01:00","skill":"task-routing","runId":"PRIVATE-ID","event":"started","prompt":"PRIVATE-TEXT"}' \
  '{"at":"2026-11-12T12:00:00Z","skillName":"task-routing","runId":"PRIVATE-ID","event":"completed","artifactPaths":["/PRIVATE-PATH"]}' \
  '{"at":"2026-11-12","skill":"task-routing","runId":"PRIVATE-ID","event":"finished"}' \
  '{"at":"2026-11-12","skill":"task-routing","runId":"start-only","event":"started"}' \
  '{"at":"2026-11-12","skill":"test-driven-development","runId":"PRIVATE-ID","event":"blocked"}' \
  '{"at":"2026-11-12","skill":"test-driven-development","event":"started"}' \
  '{"at":"2026-11-13T00:00:00Z","skill":"outside-window","runId":"next","event":"started"}' \
  'not-json' > "$fixture/audit.jsonl"
result="$(SKILL_AUDIT_ROOT="$fixture" python3 "$audit" --since 2026-11-12 --until 2026-11-13)"
assert_eq "$?" '0' 'skill audit: 既定の監査ルートを読める'
assert_not_contains "$result" 'PRIVATE-' 'skill audit: ID・本文・パスを出力しない'
assert_not_contains "$result" 'outside-window' 'skill audit: 終了日を含めない'
printf '%s\n' "$result" | python3 -c '
import json, sys
r = json.load(sys.stdin)
s = r["skills"]
assert s["task-routing"]["started"] == 2
assert s["task-routing"]["paired_runs"] == 1
assert s["task-routing"]["start_only_runs"] == 1
assert s["test-driven-development"]["end_only_runs"] == 1
assert r["ignored"] == {"invalid_json_or_date": 1, "uncorrelated_lifecycle_event": 1}
'
assert_eq "$?" '0' 'skill audit: UTC 日付、旧形式、未対応の開始・終端を区別する'
python3 "$audit" --log "$fixture/missing.jsonl" >/dev/null 2>&1
assert_eq "$?" '1' 'skill audit: ログ未取得を空の集計と区別する'
python3 "$audit" --since 2026-11-13 --until 2026-11-12 >/dev/null 2>&1
assert_eq "$?" '2' 'skill audit: 逆転した日付範囲を拒否する'

assert_summary
