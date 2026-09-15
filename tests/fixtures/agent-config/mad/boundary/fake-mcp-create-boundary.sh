#!/usr/bin/env bash
# 親が mcp__paseo__create_agent を呼ぶ境界の test double。
# create の前に runner の --prepare-create で request を strict 検証して一回性
# marker を取り、取れたときだけ create payload を観測記録に残して accepted
# response を書く。marker を取れない呼び出しは create を呼ばない。
set -u

request=""
response_out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --request) request="${2:-}"; shift 2 ;;
    --response-out) response_out="${2:-}"; shift 2 ;;
    *) exit 2 ;;
  esac
done
[ -n "$request" ] && [ -n "$response_out" ] || exit 2
[ "$(basename "$request")" = "mcp-create.json" ] || exit 2
attempt_dir="$(cd "$(dirname "$request")" && pwd -P)" || exit 2

validator="${PASEO_MAD_VALIDATOR:-$HOME/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate}"
share_dir="${PASEO_MAD_SHARE_DIR:-$HOME/.local/share/agent-config}"
[ -f "$validator" ] || exit 2

# 未検証の request と二重 create を防ぐ。観測も応答も marker を取った後で書く。
bash "$validator" --prepare-create --share-dir "$share_dir" --attempt-dir "$attempt_dir" \
  >/dev/null 2>&1 || exit 2

# 公式 MCP tool が受け取る引数と同じ 6 key だけを観測する。
if [ -n "${PASEO_FAKE_MCP_OBSERVED:-}" ]; then
  jq -ce '{
    title, workspaceId, initialPrompt, notifyOnFinish, provider,
    settings: {modeId: .settings.modeId, thinkingOptionId: .settings.thinkingOptionId, features: .settings.features}
  }' "$request" > "$PASEO_FAKE_MCP_OBSERVED.tmp" || exit 2
  chmod 600 "$PASEO_FAKE_MCP_OBSERVED.tmp"
  mv "$PASEO_FAKE_MCP_OBSERVED.tmp" "$PASEO_FAKE_MCP_OBSERVED"
fi

if [ "${PASEO_FAKE_MCP_REJECT:-0}" = "1" ]; then
  response='{"status":"rejected"}'
elif [ "${PASEO_FAKE_DUPLICATE_ACCEPTED_CHILD_REF:-0}" = "1" ]; then
  response='{"status":"accepted","childRef":"11111111-1111-4111-8111-111111111111","childRef":"22222222-2222-4222-8222-222222222222"}'
elif [ "${PASEO_FAKE_PROTO_CHILD_REF:-0}" = "1" ]; then
  response='{"status":"accepted","childRef":"11111111-1111-4111-8111-111111111111","__proto__":{"unexpected":true}}'
elif [ "${PASEO_FAKE_DOT_CHILD_REF:-0}" = "1" ]; then
  response='{"status":"accepted","childRef":"."}'
else
  response="${PASEO_FAKE_MCP_RESPONSE:-{\"status\":\"accepted\",\"childRef\":\"11111111-1111-4111-8111-111111111111\"}}"
fi

( umask 077; printf '%s' "$response" > "$response_out.tmp" ) || exit 2
chmod 600 "$response_out.tmp"
mv "$response_out.tmp" "$response_out" || exit 2
