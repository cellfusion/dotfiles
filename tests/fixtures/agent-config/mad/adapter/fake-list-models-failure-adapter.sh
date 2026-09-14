#!/usr/bin/env bash
set -u

case "${1:-}" in
  list-providers)
    printf '%s\n' '{"providers":[{"id":"claude","available":true,"modeIds":["auto"]},{"id":"claude-lab","available":false,"modeIds":[]},{"id":"codex","available":true,"modeIds":["auto"]},{"id":"codex-lab","available":false,"modeIds":[]},{"id":"opencode","available":false,"modeIds":[]},{"id":"pi","available":false,"modeIds":[]}]}'
    ;;
  list-models) exit 1 ;;
  *) exit 2 ;;
esac
