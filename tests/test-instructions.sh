#!/usr/bin/env bash
# 配布される agent-skills 文書に退役した SDD 名が残っていないことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

matches="$(rg -ni 'sdd|subagent-driven-development' \
  "$CHEZMOI_SOURCE/.chezmoitemplates/agent-skills" || true)"
assert_eq "$matches" "" \
  'agent-skills: SDD と subagent-driven-development の参照を残さない'

assert_summary
