#!/usr/bin/env bash
# A fresh zsh must load toolchain environment definitions without inherited exports.
set -u
. "$(dirname "$0")/lib/assert.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"
mkdir -p "$home/.config/zsh"
cp "$CHEZMOI_SOURCE/dot_zshenv" "$home/.zshenv"
cp "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshenv" "$home/.config/zsh/.zshenv"

probe='printf "%s\n" "$ANDROID_HOME" "$ANDROID_SDK_ROOT" "$ANDROID_USER_HOME" "$CARGO_HOME" "$RUSTUP_HOME" "$DENO_INSTALL" "$AWS_CONFIG_FILE" "${path[(r)$HOME/.dotnet/tools]}"'
expected="$(printf '%s\n' \
  "$home/Library/Android/sdk" \
  "$home/Library/Android/sdk" \
  "$home/.local/share/android" \
  "$home/.local/share/cargo" \
  "$home/.local/share/rustup" \
  "$home/.local/share/deno" \
  "$home/.config/aws/config" \
  "$home/.dotnet/tools")"

for flags in -c -lc -ic -lic; do
  status=0
  output="$(env -i HOME="$home" PATH=/usr/bin:/bin TERM=xterm-256color \
    /bin/zsh "$flags" "$probe" 2>&1)" || status=$?
  assert_eq "$status" 0 "$flags: fresh shell starts successfully"
  assert_eq "$output" "$expected" "$flags: toolchain paths do not depend on inherited environment"
done

# Optional integrations must not break a new interactive shell or replace its SSH agent.
cp "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshrc" "$home/.config/zsh/.zshrc"
for flags in -ic -lic; do
  status=0
  output="$(env -i HOME="$home" PATH=/usr/bin:/bin TERM=xterm-256color \
    TERM_PROGRAM=kiro SSH_AUTH_SOCK="$tmp/existing-agent.sock" \
    /bin/zsh "$flags" 'printf "%s\n" "$SSH_AUTH_SOCK"' 2>&1)" || status=$?
  assert_eq "$status" 0 "$flags: missing optional tools do not prevent shell startup"
  assert_eq "$output" "$tmp/existing-agent.sock" \
    "$flags: no startup errors and the existing SSH agent is preserved"
done

status=0
output="$(env -i HOME="$home" ZDOTDIR="$home/.config/zsh" PATH=/usr/bin:/bin \
  /bin/zsh -c "$probe" 2>&1)" || status=$?
assert_eq "$status" 0 'explicit ZDOTDIR: shell starts successfully'
assert_eq "$output" "$expected" 'explicit ZDOTDIR: environment matches bootstrap startup'

rm "$home/.config/zsh/.zshenv"
status=0
output="$(env -i HOME="$home" PATH=/usr/bin:/bin \
  /bin/zsh -c 'printf "%s\n" "$ZDOTDIR"' 2>&1)" || status=$?
assert_eq "$status" 0 'first install: missing environment file does not prevent shell startup'
assert_eq "$output" "$home/.config/zsh" 'first install: bootstrap still selects the configuration directory'

assert_summary
