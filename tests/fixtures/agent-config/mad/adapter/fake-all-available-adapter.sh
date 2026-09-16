#!/usr/bin/env bash
set -u

if [ -n "${EXPECTED_PASEO_MAD_SHARE_DIR:-}" ] &&
   [ "${PASEO_MAD_SHARE_DIR:-}" != "$EXPECTED_PASEO_MAD_SHARE_DIR" ]; then
  exit 9
fi

case "${1:-}" in
  list-providers)
    printf '%s\n' '{"providers":[{"id":"claude","available":true,"modeIds":["auto"]},{"id":"claude-lab","available":true,"modeIds":["auto"]},{"id":"codex","available":true,"modeIds":["auto"]},{"id":"codex-lab","available":true,"modeIds":["auto"]},{"id":"opencode","available":true,"modeIds":["auto"]},{"id":"pi","available":true,"modeIds":["auto"]}]}'
    ;;
  list-models)
    [ "${2:-}" = "--provider" ] || exit 2
    case "${3:-}" in
      claude) printf '%s\n' '{"provider":"claude","models":[{"id":"sample-think","thinkingOptionIds":["high"]},{"id":"sample-deep","thinkingOptionIds":["max"]}]}' ;;
      claude-lab) printf '%s\n' '{"provider":"claude-lab","models":[{"id":"sample-think","thinkingOptionIds":["high"]},{"id":"sample-deep","thinkingOptionIds":["max"]}]}' ;;
      codex) printf '%s\n' '{"provider":"codex","models":[{"id":"sample-light","thinkingOptionIds":["medium"]},{"id":"sample-work","thinkingOptionIds":["high"]}]}' ;;
      codex-lab) printf '%s\n' '{"provider":"codex-lab","models":[{"id":"sample-lab-work","thinkingOptionIds":["high"]}]}' ;;
      opencode) printf '%s\n' '{"provider":"opencode","models":[]}' ;;
      pi) printf '%s\n' '{"provider":"pi","models":[]}' ;;
      *) exit 2 ;;
    esac
    ;;
  wait-agent)
    [ "${2:-}" = "--child-ref" ] && [ "${4:-}" = "--timeout" ] || exit 2
    [ -n "${3:-}" ] && [ -n "${5:-}" ] || exit 2
    printf '%s\n' "{\"status\":\"${PASEO_FAKE_WAIT_STATUS:-idle}\"}"
    ;;
  *) exit 2 ;;
esac
