#!/usr/bin/env bash
set -u

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
    printf '%s\n' '{"status":"rejected"}'
    exit 1
    ;;
  *) exit 2 ;;
esac
