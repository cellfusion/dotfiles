#!/usr/bin/env bash
# 退役 skill の配布先を exact path で検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

FIXTURES="${PASEO_LEGACY_FIXTURES:-$CHEZMOI_SOURCE/tests/fixtures/agent-config}"
LEGACY="$FIXTURES/legacy"
fixture="$LEGACY/chezmoiremove-required-paths.txt"

fixture_status="$(test -f "$fixture" && test ! -L "$fixture" && test -r "$fixture" &&
  echo yes || echo no)"
assert_eq "$fixture_status" yes 'fixture: chezmoiremove-required-paths.txt が regular file'


managed="$(chezmoi managed --source "$CHEZMOI_SOURCE" --include=files,symlinks 2>/dev/null || true)"
if [ "$fixture_status" = yes ]; then
  while read -r destination; do
    [ -n "$destination" ] || continue
    case "$destination" in
      .agents/skills/*)
        assert_not_contains "$managed" "$destination" \
          "distribution: $destination を配らない"
        ;;
    esac
  done < "$fixture"
fi

assert_summary
