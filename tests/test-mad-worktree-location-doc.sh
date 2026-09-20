#!/usr/bin/env bash
# Verify that human worktrees and strict MAD worktrees have separate locations and policies.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

using=$(awk '{print}' "$REPO_ROOT/.chezmoitemplates/agent-skills/using-git-worktrees/SKILL.md")
worktrees_doc=$(awk '{print}' "$REPO_ROOT/private_dot_config/docs/worktrees.md")
chezmoiremove=$(awk '{print}' "$REPO_ROOT/.chezmoiremove")
chezmoiremove+=$'\n'

assert_not_contains "$using" 'MAD' 'using skill: no strict MAD-specific section'
assert_contains "$using" 'WORKTREE_ROOT="${WORKTREE_ROOT:-$HOME/.local/state/worktrees}"' \
  'using skill: external worktree root is the default'
assert_contains "$using" 'git worktree add' 'using skill: Git fallback is documented'
assert_contains "$using" 'Do not edit `.gitignore`' 'using skill: no automatic ignore mutation'
assert_contains "$using" 'Never run `npm install`' 'using skill: no automatic dependency execution'
assert_contains "$using" 'sandbox permissions' 'using skill: sandbox failures are explicit'

assert_not_contains "$worktrees_doc" 'worktrunk/agent.toml' 'docs: old agent.toml reference is absent'
assert_not_contains "$worktrees_doc" 'orchestration/<run-id>/' 'docs: old run location is absent'
assert_contains "$worktrees_doc" '${MAD_STATE_DIR}/runs' 'docs: run directory location'
assert_contains "$worktrees_doc" '${MAD_STATE_DIR}/worktrees' 'docs: worktree directory location'
assert_contains "$worktrees_doc" 'mcp__paseo__create_workspace' 'docs: Paseo local workspace call'
assert_contains "$worktrees_doc" 'mad-worktree remove' 'docs: cleanup command'

[ -e "$REPO_ROOT/private_dot_config/worktrunk/agent.toml" ] &&
  fail_check 'agent.toml is removed' || pass 'agent.toml is removed'
[ -e "$REPO_ROOT/private_dot_config/worktrunk/config.toml" ] &&
  pass 'human config remains' || fail_check 'human config remains'

assert_contains "$chezmoiremove" $'\n.config/worktrunk/agent.toml\n' \
  '.chezmoiremove removes distributed agent.toml'

assert_summary
