#!/usr/bin/env bash
# 実機の private-data.toml が定義する session 名と、正本 agent-config.json の
# environments の key が一致することを検証する。
# 2 つのファイルは clone した人のマシンにしかないので、無いときは assert を実行しない。
set -u
. "$(dirname "$0")/lib/assert.sh"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
private_data="$config_home/chezmoi/private-data.toml"
agent_config="$config_home/chezmoi/agent-config.json"

if [ -f "$private_data" ] && [ -f "$agent_config" ]; then
  sessions="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    --config "$private_data" --config-format toml \
    '{{ range .environments }}{{ .session }}{{ "\n" }}{{ end }}' | sort)"
  environment_keys="$(jq -r '.environments | keys[]' "$agent_config" | sort)"
  assert_eq "$sessions" "$environment_keys" \
    "環境名: private-data.toml の session と正本の environments が一致する"
fi

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
