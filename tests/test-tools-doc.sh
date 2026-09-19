#!/usr/bin/env bash
# MAD の配布 script 文書を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/tools.md")"

assert_contains "$doc" 'MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"' \
  'docs: task-brief の絶対 script path を記録する'
assert_contains "$doc" '`MAD_SCRIPTS`配下の5 script' \
  'docs: MAD script の本数を5本と記録する'
assert_contains "$doc" 'MAD_REVIEW_BUNDLE="$MAD_SCRIPTS/review-bundle"' \
  'docs: review-bundle の記録を保持する'

assert_summary
