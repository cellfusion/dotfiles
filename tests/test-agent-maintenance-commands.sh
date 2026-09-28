#!/usr/bin/env bash
# Pi/Codex の update は実 CLI、通常の AI CLI 起動は cwd-aware agent wrapper を使う。
set -u

source "$(dirname "$0")/lib/assert.sh"

root="$CHEZMOI_SOURCE"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

data="$tmp/data.json"
printf '%s\n' '{"environments":[{"session":"restricted","agents":[]}]}' > "$data"
rendered="$tmp/agent-environments.zsh"
if chezmoi execute-template --source "$root" --override-data-file "$data" \
  --file "$root/private_dot_config/zsh/agent-environments.zsh.tmpl" > "$rendered"; then
  pass 'zsh environment template renders for an isolated environment'
else
  fail_check 'zsh environment template renders for an isolated environment'
  assert_summary
  exit 1
fi

mock_bin="$tmp/bin"
mkdir -p "$mock_bin"
for tool in pi codex claude omp agent; do
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s %s\n" "${0##*/}" "$*" >> "$COMMAND_LOG"' > "$mock_bin/$tool"
  chmod +x "$mock_bin/$tool"
done

calls="$tmp/calls"
output=''
status=0
output="$(AGENT_ENV=restricted COMMAND_LOG="$calls" PATH="$mock_bin:$PATH" \
  zsh -c '
    source "$1"
    pi update
    codex update
    claude prompt
    codex exec
    pi prompt
    omp prompt
  ' zsh "$rendered" 2>&1)" || status=$?
assert_eq "$status" 0 'pi/codex の update と通常の wrapper 起動が成功する'
recorded_calls=''
[ -f "$calls" ] && recorded_calls="$(<"$calls")"
assert_eq "$recorded_calls" $'pi update\ncodex update\nagent --family=claude -- prompt\nagent --family=codex -- exec\nagent --family=pi -- prompt\nagent --family=omp -- prompt' \
  'update は実 CLI、通常起動は family wrapper に渡る'
assert_eq "$output" '' 'wrapper routing は拒否メッセージを出さない'

assert_summary
