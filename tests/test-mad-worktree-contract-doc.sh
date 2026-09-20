#!/usr/bin/env bash
# 契約文書と配布文書から Paseo の worktree 作成と archive が消えたことを検査する。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

CONTRACT="$REPO_ROOT/.chezmoitemplates/agent-skills/_manual-orchestration.md"
SKILL="$REPO_ROOT/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md"
TOOLS="$REPO_ROOT/private_dot_config/docs/tools.md"

contract="$(cat "$CONTRACT")"
skill="$(cat "$SKILL")"
tools="$(cat "$TOOLS")"

assert_not_contains "$contract" 'isolation: worktree' '契約文書は isolation: worktree を書かない'
assert_not_contains "$contract" 'branch-off' '契約文書は branch-off を書かない'
assert_not_contains "$contract" 'archive' '契約文書は archive を書かない'
assert_not_contains "$skill" 'isolation: worktree' 'スキルは isolation: worktree を書かない'
assert_not_contains "$skill" 'branch-off' 'スキルは branch-off を書かない'
assert_not_contains "$skill" 'archive_workspace' 'スキルは archive_workspace を書かない'
assert_contains "$contract" 'isolation: local' '契約文書は isolation: local を書く'

assert_not_contains "$contract" 'workspaces.json' '契約文書は workspaces.json を書かない'
assert_contains "$contract" 'worktrees.json' '契約文書は worktrees.json を書く'
assert_not_contains "$tools" 'workspaces.json' '配布文書は workspaces.json を書かない'
assert_not_contains "$tools" 'archive_workspace' '配布文書は archive_workspace を書かない'
assert_contains "$tools" 'mad-worktree remove' '配布文書は mad-worktree remove を書く'
assert_contains "$tools" 'worktrees.json' '配布文書は worktrees.json を書く'

assert_contains "$contract" '${MAD_STATE_DIR}/runs' '契約文書は run directory の置き場所を決める'
assert_contains "$contract" 'backend_handle' 'attempt state の key に backend_handle がある'
assert_contains "$contract" 'liveness' 'attempt state の key に liveness がある'
assert_contains "$contract" 'review-package.diff' '契約文書は review-package.diff の名前を残す'
assert_contains "$skill" 'mad-worktree' 'スキルは隔離の担当を mad-worktree と書く'

# 台帳の base は mad-worktree が解決した 40 桁 commit である。run state 側の表記が
# branch 名や短縮 SHA だと、validator の文字列一致が必ず落ちる。
assert_contains "$contract" '`base` は解決済みの 40 桁 commit とし、branch 名や短縮 SHA を書かない' \
  '契約文書は run state の base を 40 桁 commit と定める'

# pending の attempt state の 2 key は 1 本目と 2 本目の決定であり、4 本目は変えない。
contract_module="$REPO_ROOT/private_dot_local/private_share/agent-config/mad-contract.js"
assert_contains "$(cat "$contract_module")" \
  "MAD_ATTEMPT_STATE_PENDING_KEYS = ['state', 'create_accepted']" \
  'pending の attempt state は 2 key のままである'

assert_summary
