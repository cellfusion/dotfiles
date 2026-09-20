#!/usr/bin/env bash
# Verify the English strict-MAD contract and its executable path references.
set -u
. "$(dirname "$0")/lib/assert.sh"

mad_contract="$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/_manual-orchestration.md"
mad_skill="$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills/multi-agent-development/SKILL.md"
mad_validator="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"

assert_eq "$(MANUAL_ORCHESTRATION_PASEO_CLI_AVAILABLE=1 bash "$mad_validator" --select-backend)" \
  '{"backend":"paseo-cli","backend_reason":"Paseo CLI available"}' \
  'backend: CLI is preferred when available'
assert_eq "$(MANUAL_ORCHESTRATION_PASEO_MCP_AVAILABLE=1 bash "$mad_validator" --select-backend)" \
  '{"backend":"paseo-mcp","backend_reason":"Paseo MCP available"}' \
  'backend: MCP remains an explicit fallback'

assert_before() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*"$3"*) _pass "$4" ;;
    *) _fail "$4" "expected order: $2 -> $3" ;;
  esac
}

contract="$(<"$mad_contract")"
skill="$(<"$mad_skill")"

for token in MAD_TASK_BRIEF brief.md --waves --check-implement-result PROJECT_ROOT 'merge --abort' \
  'MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"' 'MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"' \
  'MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"' 'paseo-cli' 'mad-attempt-outcome-v1' \
  'inspect-agent --child-ref' 'backend_handle' 'liveness' 'worktrees.json' '${MAD_STATE_DIR}/runs'; do
  assert_contains "$contract" "$token" "contract contains $token"
done

for token in MAD_TASK_BRIEF MAD_STATE_DIR MAD_WORKTREE MAD_PROGRESS 'paseo-cli' 'mad-worktree' \
  'strict contract' 'plan-auditor' 'review scope'; do
  assert_contains "$skill" "$token" "skill contains $token"
done

assert_before "$contract" 'task excerpt -> execution context' 'prepare marker -> create' \
  'contract: context is prepared before create'
assert_before "$contract" '--check-implement-result' 'BLOCKED' \
  'contract: result validation precedes blocked handling'
assert_before "$contract" 'merge --no-ff' 'merge --abort' \
  'contract: merge success and conflict paths are ordered'
assert_before "$skill" 'dependency gate' 'plan-auditor' \
  'skill: dependency validation precedes plan audit'

assert_contains "$contract" 'raw responses' 'contract: raw responses are excluded from artifacts'
assert_contains "$contract" '0600' 'contract: private artifacts are required'
assert_contains "$contract" 'waiting_for_user' 'contract: user decision state exists'

assert_summary
