#!/usr/bin/env bash
# run_onchange_after_90-agent-envs.sh.tmpl の安全な実行順序を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SCRIPT="$(mktemp)"
fixture="$(mktemp -d)"
trap 'rm -rf "$SCRIPT" "$fixture"' EXIT

chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  < "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_90-agent-envs.sh.tmpl" > "$SCRIPT"
script_body="$(cat "$SCRIPT")"

assert_contains "$script_body" "#!/usr/bin/env bash" "shebang がある"
assert_contains "$script_body" "set -eu" "set -eu がある"
assert_not_contains "$script_body" "{{" "未展開のテンプレート構文が残っていない"
assert_not_contains "$script_body" "private-data.toml" "hook: 旧 private-data 経路を持たない"
assert_not_contains "$script_body" "setup_paseo_provider" "hook: 旧 provider 書き込みを持たない"
assert_contains "$script_body" "setupDirectories" "hook: directory setup を呼ぶ"
assert_contains "$script_body" "generate-paseo-config" "hook: 生成 CLI を呼ぶ"
assert_eq "$(grep -c 'generate-paseo-config' "$SCRIPT")" "1" "hook: CLI の呼び出しは一回だけ"

fake_home="$fixture/home"
xdg="$fixture/config"
share="$fake_home/.local/share/agent-config"
fake_bin="$fake_home/.local/bin"
calls="$fixture/generator-calls"
mkdir -p "$share" "$fake_bin" "$xdg/chezmoi" "$xdg/claude" "$xdg/codex"
cp "$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/config-validator.js" "$share/"
cp "$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/config-types.js" "$share/"
cp "$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/agent-config.schema.json" "$share/"
cp "$CHEZMOI_SOURCE/private_dot_local/private_share/agent-config/directory-setup.js" "$share/"
cp "$CHEZMOI_SOURCE/tests/fixtures/agent-config/valid-v1.json" "$xdg/chezmoi/agent-config.json"
mkdir -p "$fake_home/.paseo"
cp "$CHEZMOI_SOURCE/tests/fixtures/agent-config/targets/base.json" "$fake_home/.paseo/config.json"
mkdir -p "$xdg/claude/agents" "$xdg/claude/commands" "$xdg/claude/skills" \
  "$xdg/claude/hooks" "$xdg/codex/agents"
for name in CLAUDE.md settings.json; do : > "$xdg/claude/$name"; done
: > "$xdg/codex/AGENTS.md"

cat > "$fake_bin/generate-paseo-config" <<'EOF'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$#" > "$CALLS"
[ "$#" -eq 0 ]
[ -L "$XDG_CONFIG_HOME/claude_lab/agents" ]
EOF
chmod +x "$fake_bin/generate-paseo-config"
cat > "$fake_bin/mise" <<'EOF'
#!/usr/bin/env bash
set -eu
[ "$1" = exec ]
shift
[ "$1" = -- ]
shift
exec "$@"
EOF
chmod +x "$fake_bin/mise"

node_bin="$(dirname "$(command -v node)")"
if HOME="$fake_home" XDG_CONFIG_HOME="$xdg" CALLS="$calls" PATH="$node_bin:/usr/bin:/bin" \
  bash "$SCRIPT" >/dev/null 2>&1; then hook_status=0; else hook_status=$?; fi
assert_eq "$hook_status" "0" "hook: setup 成功後に CLI を一回呼ぶ"
assert_eq "$(cat "$calls")" "0" "hook: CLI に引数を渡さない"
assert_eq "$(readlink "$xdg/claude_lab/agents")" "../claude/agents" "hook: setup が相対 symlink を作る"

rm -f "$xdg/claude_lab/agents"
printf 'real file\n' > "$xdg/claude_lab/agents"
rm -f "$calls"
if HOME="$fake_home" XDG_CONFIG_HOME="$xdg" CALLS="$calls" PATH="$node_bin:/usr/bin:/bin" \
  bash "$SCRIPT" >/dev/null 2>&1; then failed_setup_status=0; else failed_setup_status=$?; fi
assert_eq "$failed_setup_status" "2" "hook: setup failure は exit 2"
assert_eq "$(test -e "$calls" && echo called || echo not-called)" "not-called" "hook: setup failure 後に CLI を呼ばない"
assert_eq "$(cat "$xdg/claude_lab/agents")" "real file" "hook: setup failure で実体を置換しない"

rm -f "$xdg/claude_lab/agents"
ln -s ../claude/agents "$xdg/claude_lab/agents"
rm -f "$fake_home/.paseo/config.json" "$calls"
if HOME="$fake_home" XDG_CONFIG_HOME="$xdg" CALLS="$calls" PATH="$node_bin:/usr/bin:/bin" \
  bash "$SCRIPT" >/dev/null 2>&1; then skip_status=0; else skip_status=$?; fi
assert_eq "$skip_status" "0" "hook: target が無ければ skip する"
assert_eq "$(test -e "$fake_home/.paseo/config.json" && echo yes || echo no)" "no" "hook: target が無いとき config を作らない"
assert_eq "$(cat "$calls")" "0" "hook: skip 時も CLI を一回呼ぶ"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
test "$TESTS_FAILED" -eq 0
