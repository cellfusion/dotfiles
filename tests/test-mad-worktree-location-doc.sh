#!/usr/bin/env bash
# MAD の worktree と run ディレクトリの置き場所を説明する文書を検査する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

using="$(cat "$REPO_ROOT/.chezmoitemplates/agent-skills/using-git-worktrees/SKILL.md")"
worktrees_doc="$(cat "$REPO_ROOT/private_dot_config/docs/worktrees.md")"
# $(cat) は末尾の改行を落とす。ファイル末尾の行も行単位で照合できるよう改行を補う。
chezmoiremove="$(cat "$REPO_ROOT/.chezmoiremove")"$'\n'

assert_not_contains "$using" 'の波は `.worktrees/` を使う' 'MAD の波が .worktrees を使う記述は残らない'
assert_not_contains "$using" '`.worktrees/` の ignore を確認する' 'MAD 用の ignore 確認は残らない'
assert_not_contains "$using" 'MAD 用' 'MAD 用の節は残らない'
assert_not_contains "$using" 'multi-agent-development' 'MAD への参照は残らない'
# 人が 1c で手作業の worktree を切る箇所と chezmoi の source directory の例は残す。
assert_contains "$using" 'ls -d .worktrees 2>/dev/null' '1c のディレクトリ探索は残る'
assert_contains "$using" 'git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null' \
  '1c の安全確認は残る'

assert_not_contains "$worktrees_doc" 'worktrunk/agent.toml' 'agent.toml への参照は残らない'
assert_not_contains "$worktrees_doc" 'orchestration/<run-id>/' 'run ディレクトリの旧い置き場所は残らない'
assert_not_contains "$worktrees_doc" 'MAD の run ディレクトリ・レビュー package' \
  '成果物の列挙から run ディレクトリを外す'
assert_contains "$worktrees_doc" '${MAD_STATE_DIR}/runs' 'run ディレクトリの置き場所を書く'
assert_contains "$worktrees_doc" '${MAD_STATE_DIR}/worktrees' 'worktree の置き場所を書く'
assert_contains "$worktrees_doc" 'mcp__paseo__create_workspace' 'Paseo backend の呼び出しは残る'
assert_contains "$worktrees_doc" 'mad-worktree remove' '片付けの手段を書く'

[ -e "$REPO_ROOT/private_dot_config/worktrunk/agent.toml" ] &&
  fail_check 'agent.toml は削除されている' ||
  pass 'agent.toml は削除されている'
[ -e "$REPO_ROOT/private_dot_config/worktrunk/config.toml" ] &&
  pass '人用の config.toml は残る' ||
  fail_check '人用の config.toml は残る'

assert_contains "$chezmoiremove" $'\n.config/worktrunk/agent.toml\n' \
  '.chezmoiremove が配布済みの agent.toml を回収する'

assert_summary
