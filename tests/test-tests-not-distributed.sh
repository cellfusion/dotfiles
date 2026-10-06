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

assert_summary
