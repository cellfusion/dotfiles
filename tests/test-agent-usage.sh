#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib/assert.sh"
if node --test "$CHEZMOI_SOURCE/tests/test-agent-usage.js"; then
  pass 'account quota freshness, unknown windows, source separation and refresh evidence'
else
  fail_check 'account quota boundary tests'
fi
assert_summary
