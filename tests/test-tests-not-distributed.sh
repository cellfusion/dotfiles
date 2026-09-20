#!/usr/bin/env bash
# tests/ を chezmoi が配らないことを検査する。2 行のどちらかが消えると、
# ここに置いたテストが ~/tests/ へ配られる。
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
. "$(dirname "$0")/lib/assert.sh"

ignore="$(cat "$REPO_ROOT/.chezmoiignore")"
assert_contains "$ignore" $'\ntests\n' '.chezmoiignore は tests を持つ'
assert_contains "$ignore" $'\ntests/**\n' '.chezmoiignore は tests/** を持つ'
assert_contains "$ignore" $'\nCLAUDE.md\n' '.chezmoiignore は repository-local CLAUDE.md を配らない'

remove="$(cat "$REPO_ROOT/.chezmoiremove")"
assert_contains "$remove" $'\nCLAUDE.md\n' '.chezmoiremove は home-level CLAUDE.md を回収する'

claude_md="$(cat "$REPO_ROOT/CLAUDE.md")"
assert_contains "$claude_md" 'tests/lib/assert.sh' 'CLAUDE.md は共通 assert の場所を書く'
assert_contains "$claude_md" 'bash tests/run-tests.sh' 'CLAUDE.md は runner の回し方を書く'
assert_contains "$claude_md" 'bash tests/test-tools-doc.sh' 'CLAUDE.md は単体実行の例を書く'

assert_summary
