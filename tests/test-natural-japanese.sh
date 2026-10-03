#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib/assert.sh"

# Resolve cached Sudachi dependencies only; never fetch packages during the suite.
status=0
output="$(uv run --offline "$CHEZMOI_SOURCE/tests/test-natural-japanese.py" \
  "$CHEZMOI_SOURCE/private_dot_agents/skills/natural-japanese/scripts" 2>&1)" || status=$?
printf '%s\n' "$output"
if [ "$status" -ne 0 ]; then
  fail_check 'Japanese writing tool regressions (requires uv and cached Sudachi dependencies)'
else
  pass 'Japanese writing tool regressions'
fi
assert_summary
