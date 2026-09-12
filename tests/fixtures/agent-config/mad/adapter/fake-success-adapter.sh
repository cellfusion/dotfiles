#!/usr/bin/env bash
set -u

if [ -n "${EXPECTED_PASEO_MAD_SHARE_DIR:-}" ] &&
   [ "${PASEO_MAD_SHARE_DIR:-}" != "$EXPECTED_PASEO_MAD_SHARE_DIR" ]; then
  exit 9
fi

case "${1:-}" in
  list-providers)
    printf '%s\n' '{"providers":[{"id":"claude","available":true,"modeIds":["auto"]},{"id":"claude-lab","available":false,"modeIds":[]},{"id":"codex","available":true,"modeIds":["auto"]},{"id":"codex-lab","available":false,"modeIds":[]},{"id":"opencode","available":false,"modeIds":[]},{"id":"pie","available":false,"modeIds":[]}]}'
    ;;
  list-models)
    [ "${2:-}" = "--provider" ] || exit 2
    case "${3:-}" in
      claude) printf '%s\n' '{"provider":"claude","models":[{"id":"sample-think","thinkingOptionIds":["high"]},{"id":"sample-deep","thinkingOptionIds":["max"]}]}' ;;
      codex) printf '%s\n' '{"provider":"codex","models":[{"id":"sample-light","thinkingOptionIds":["medium"]},{"id":"sample-work","thinkingOptionIds":["high"]}]}' ;;
      *) exit 2 ;;
    esac
    ;;
  create-agent)
    [ "${2:-}" = "--request" ] || exit 2
    [ -f "${3:-}" ] && [ ! -L "${3:-}" ] || exit 2
    printf '%s\n' '{"status":"accepted"}'
    ;;
  *) exit 2 ;;
esac
