#!/usr/bin/env bash
# 環境で無効な agent でも CLI 自身の update サブコマンドは実行できる。
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
for tool in pi codex; do
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
    if pi prompt; then exit 11; fi
    if codex exec; then exit 12; fi
    if claude update; then exit 13; fi
  ' zsh "$rendered" 2>&1)" || status=$?
assert_eq "$status" 0 'pi/codex の update を許可し、通常起動は引き続き拒否する'
recorded_calls=''
[ -f "$calls" ] && recorded_calls="$(<"$calls")"
assert_eq "$recorded_calls" $'pi update\ncodex update' \
  'pi update と codex update が実 CLI にそのまま渡る'
assert_contains "$output" 'not configured for this environment' \
  '対話・実行サブコマンドは引き続き環境制限される'

assert_summary
