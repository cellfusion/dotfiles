#!/usr/bin/env bash
# Brew 上の同名コマンドが native 導入を抑止しないことと installer の失敗を検証する。
set -eu
. "$(dirname "$0")/lib/assert.sh"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
rendered="$scratch/runtimes.sh"
chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  < "$CHEZMOI_SOURCE/.chezmoiscripts/run_onchange_after_20-runtimes.sh.tmpl" > "$rendered"
mkdir -p "$scratch/bin"
cat > "$scratch/bin/curl" <<'CURL'
#!/bin/sh
for arg do url="$arg"; done
case "$url" in
  *get.chezmoi.io*) target="$HOME/.local/bin/chezmoi" ;;
  *mise.run*) target="$HOME/.local/bin/mise" ;;
  *bun.sh/install*) target="$BUN_INSTALL/bin/bun" ;;
  *astral.sh/uv/install.sh*)
    cat <<'UV'
[ "${UV_NO_MODIFY_PATH:-}" = 1 ] || exit 71
[ "$UV_INSTALL_DIR" = "$HOME/.local/bin" ] || exit 72
mkdir -p "$UV_INSTALL_DIR"
printf '#!/bin/sh\nexit 0\n' > "$UV_INSTALL_DIR/uv"
chmod +x "$UV_INSTALL_DIR/uv"
UV
    exit 0 ;;
  *sh.rustup.rs*) target="$CARGO_HOME/bin/rustup" ;;
  *herdr.dev/install.sh*) target="$HOME/.local/bin/herdr" ;;
  *) exit 73 ;;
esac
if [ "${FAIL_NATIVE_INSTALL:-}" = 1 ]; then
  printf 'exit 0\n'
  exit 0
fi
printf 'mkdir -p "%s"\n' "$(dirname "$target")"
printf 'printf '\''#!/bin/sh\\nexit 0\\n'\'' > "%s"\n' "$target"
printf 'chmod +x "%s"\n' "$target"
CURL
chmod +x "$scratch/bin/curl"
for tool in chezmoi mise bun uv rustup cargo herdr; do
  printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/$tool"
  chmod +x "$scratch/bin/$tool"
done

run_case() {
  local home="$1"
  mkdir -p "$home"
  env -i HOME="$home" PATH="$scratch/bin:/usr/bin:/bin" \
    FAIL_NATIVE_INSTALL="${FAIL_NATIVE_INSTALL:-0}" /bin/bash "$rendered" \
    > "$home/output" 2>&1
}

home="$scratch/brew-only"
if run_case "$home"; then
  for tool in chezmoi mise uv herdr; do
    if [ -x "$home/.local/bin/$tool" ]; then
      pass "Brew 上の $tool が存在しても native 実体を導入する"
    else
      fail_check "Brew 上の $tool を native 導入済みと誤認した"
    fi
  done
  [ -x "$home/.bun/bin/bun" ] && pass 'Bun の native 実体を導入する' \
    || fail_check 'Bun の native 実体がない'
  [ -x "$home/.local/share/cargo/bin/rustup" ] && pass 'rustup の native 実体を導入する' \
    || fail_check 'rustup の native 実体がない'
else
  fail_check 'Brew 版のみの状態から native 導入が完了しない'
fi

# ダウンロードが成功扱いでも実体が置かれなければ成功を報告しない。
FAIL_NATIVE_INSTALL=1
if run_case "$scratch/missing-result"; then
  fail_check 'installer が実体を置かないのに成功した'
else
  pass 'installer の出力に native 実体がなければ失敗する'
fi
assert_summary
