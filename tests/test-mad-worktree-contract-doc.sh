#!/usr/bin/env bash
# Verify that strict MAD owns Git isolation and uses external/local Paseo workspaces.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

contract="$REPO_ROOT/.chezmoitemplates/agent-skills/_manual-orchestration.md"
skill="$REPO_ROOT/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md"
tools="$REPO_ROOT/private_dot_config/docs/tools.md"

contract_text="$(<"$contract")"
skill_text="$(<"$skill")"
tools_text="$(<"$tools")"

assert_not_contains "$contract_text" 'isolation: worktree' 'contract: Paseo does not create Git worktrees'
assert_not_contains "$contract_text" 'branch-off' 'contract: branch-off is absent'
assert_not_contains "$contract_text" 'archive_workspace' 'contract: archive_workspace is absent'
assert_not_contains "$skill_text" 'isolation: worktree' 'skill: Paseo does not create Git worktrees'
assert_not_contains "$skill_text" 'branch-off' 'skill: branch-off is absent'
assert_not_contains "$skill_text" 'archive_workspace' 'skill: archive_workspace is absent'
assert_contains "$contract_text" 'isolation: local' 'contract: Paseo attaches a local workspace'
assert_not_contains "$contract_text" 'workspaces.json' 'contract: workspaces.json is absent'
assert_contains "$contract_text" 'worktrees.json' 'contract: worktrees.json is the ledger'
assert_not_contains "$tools_text" 'workspaces.json' 'tools: workspaces.json is absent'
assert_not_contains "$tools_text" 'archive_workspace' 'tools: archive_workspace is absent'
assert_contains "$tools_text" 'mad-worktree remove' 'tools: mad-worktree owns cleanup'
assert_contains "$tools_text" 'worktrees.json' 'tools: worktrees ledger is documented'
assert_contains "$contract_text" '${MAD_STATE_DIR}/runs' 'contract: run directory location'
assert_contains "$contract_text" 'backend_handle' 'contract: backend handle is retained'
assert_contains "$contract_text" 'liveness' 'contract: liveness is retained'
assert_contains "$contract_text" 'review-package.diff' 'contract: review package name'
assert_contains "$skill_text" 'mad-worktree' 'skill: mad-worktree owns isolation'
assert_contains "$contract_text" 'resolved 40-character base' 'contract: base is a full commit'

contract_module="$REPO_ROOT/private_dot_local/private_share/agent-config/mad-contract.js"
assert_contains "$(<"$contract_module")" \
  "MAD_ATTEMPT_STATE_PENDING_KEYS = ['state', 'create_accepted']" \
  'pending attempt state remains a two-key contract'

assert_summary
