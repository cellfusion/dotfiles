#!/usr/bin/env bash
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fake="$tmp/fake-paseo"
request="$tmp/request.json"

cat > "$fake" <<'SH'
#!/usr/bin/env bash
case "$1" in
  run) printf '%s\n' '{"agentId":"agent-1"}' ;;
  wait) printf '%s\n' '{"agentId":"agent-1","status":"idle"}' ;;
  stop) printf '%s\n' '{"stoppedCount":1,"agentIds":["agent-1"]}' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$fake"
cat > "$request" <<'JSON'
{
  "title": "dummy strict child",
  "workspaceId": "workspace-1",
  "initialPrompt": "Read the supplied brief.",
  "notifyOnFinish": true,
  "provider": "codex/sample-light",
  "settings": {
    "modeId": "auto",
    "thinkingOptionId": "medium",
    "features": {}
  }
}
JSON

adapter="$root/private_dot_agents/skills/multi-agent-development/scripts/executable_paseo-cli-adapter"
create="$(PASEO_CLI="$fake" "$adapter" create-agent "$request")"
assert_eq "$create" '{"status":"accepted","childRef":"agent-1"}' 'CLI adapter sanitizes create response'
wait="$(PASEO_CLI="$fake" "$adapter" wait-agent --child-ref agent-1 --timeout 30)"
assert_eq "$wait" '{"status":"idle"}' 'CLI adapter sanitizes wait response'
stop="$(PASEO_CLI="$fake" "$adapter" stop-agent --child-ref agent-1)"
assert_eq "$stop" '{"status":"stopped"}' 'CLI adapter sanitizes stop response'

assert_summary
