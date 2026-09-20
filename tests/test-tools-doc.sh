#!/usr/bin/env bash
# MAD の配布 script 文書を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/tools.md")"

assert_contains "$doc" 'MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"' \
  'docs: task-brief の絶対 script path を記録する'
assert_contains "$doc" '`MAD_SCRIPTS`配下の14 script' \
  'docs: MAD script の本数を14本と記録する'
assert_contains "$doc" 'MAD_REVIEW_BUNDLE="$MAD_SCRIPTS/review-bundle"' \
  'docs: review-bundle の記録を保持する'
assert_contains "$doc" 'MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"' \
  'docs: MAD_STATE_DIR を記録する'
assert_contains "$doc" 'MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"' \
  'docs: mad-worktree の絶対 script path を記録する'
assert_contains "$doc" 'MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"' \
  'docs: mad-progress の絶対 script path を記録する'
assert_contains "$doc" 'MAD_OUTCOME_RECORD="$MAD_SCRIPTS/mad-outcome-record"' \
  'docs: mad-outcome recorder の絶対 script path を記録する'
assert_contains "$doc" 'MAD_OUTCOME_IMPORT="$MAD_SCRIPTS/mad-outcome-import"' \
  'docs: mad-outcome importer の絶対 script path を記録する'
assert_contains "$doc" 'MAD_ROUTE_ADMIT="$TASK_ROUTING_SCRIPTS/mad-route-admit"' \
  'docs: mad-route admission の絶対 script path を記録する'
assert_contains "$doc" 'MAD_ROUTE_RECORD="$MAD_SCRIPTS/mad-route-record"' \
  'docs: mad-route recorder の絶対 script path を記録する'
assert_contains "$doc" 'MAD_ROUTE_SUMMARY="$MAD_SCRIPTS/mad-route-summary"' \
  'docs: mad-route summary の絶対 script path を記録する'
assert_contains "$doc" 'MAD_ESCALATION_CONTROLLER="$MAD_SCRIPTS/mad-escalation-controller"' \
  'docs: escalation controller の絶対 script path を記録する'

# 記録した本数が実際に配る script の本数と一致することを確かめる。
script_count="$(find "$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts" \
  -mindepth 1 -maxdepth 1 -type f | wc -l | tr -d ' ')"
assert_eq "$script_count" 14 'docs: 配る script は 14 本である'

assert_summary
