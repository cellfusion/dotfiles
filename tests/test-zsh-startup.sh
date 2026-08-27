#!/usr/bin/env bash
# zsh の起動ファイルが、対象の無い新マシンでもエラーを出さないことを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

zshrc="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshrc")"
zshenv="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zshenv")"
zprofile="$(cat "$CHEZMOI_SOURCE/private_dot_config/zsh/dot_zprofile")"

# --- BUN_INSTALL はインストール先のルートを指す ---
# bin を含めると $BUN_INSTALL/bin が二重になり、~/.bun/bin/bin/bun ができる。
# 実際にこの二重構造が現マシンに残っている。
assert_contains "$zshrc" 'export BUN_INSTALL="$HOME/.bun"' \
  "zshrc: BUN_INSTALL がインストール先のルートを指す"
assert_not_contains "$zshrc" 'BUN_INSTALL="$HOME/.bun/bin"' \
  "zshrc: BUN_INSTALL に bin を含めない"

# --- 対象が無い新マシンでも落ちない ---
# 初回起動時点では cargo も Homebrew もまだ無い。無条件に読むとエラーが出る。
assert_contains "$zshenv" '[ -f "$XDG_DATA_HOME/cargo/env" ]' \
  "zshenv: cargo/env の存在を確かめてから読む"
assert_contains "$zprofile" '[ -x /opt/homebrew/bin/brew ]' \
  "zprofile: brew の存在を確かめてから eval する"

# --- 構文として妥当 ---
for f in dot_zshrc dot_zshenv dot_zprofile; do
  err="$(zsh -n "$CHEZMOI_SOURCE/private_dot_config/zsh/$f" 2>&1 || true)"
  assert_eq "$err" "" "$f: zsh -n が通る"
done

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
