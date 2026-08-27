#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"

# --- herdr -----------------------------------------------------------------
herdr_conf="$(cat "$CHEZMOI_SOURCE/private_dot_config/herdr/config.toml")"

assert_contains "$herdr_conf" 'previous_tab = "ctrl+h"' "herdr: previous_tab が ctrl+h"
assert_contains "$herdr_conf" 'next_tab = "ctrl+l"' "herdr: next_tab が ctrl+l"
assert_contains "$herdr_conf" 'close_pane = ""' "herdr: ビルトインの close_pane が無効"
assert_contains "$herdr_conf" 'key = "ctrl+q"' "herdr: ctrl+q が割り当てられている"
assert_contains "$herdr_conf" 'confirm-close-pane' "herdr: ctrl+q が confirm-close-pane を呼ぶ"
assert_not_contains "$herdr_conf" 'key = "alt+y"' "herdr: skhd と衝突する alt+y が無い"
assert_not_contains "$herdr_conf" 'ctrl+shift+tab' "herdr: 旧タブ移動キーが残っていない"
assert_contains "$herdr_conf" 'workspace_picker = "alt+w"' "herdr: workspace_picker が alt+w"
assert_not_contains "$herdr_conf" 'ctrl+j' "herdr: 解放した ctrl+j が残っていない"
assert_not_contains "$herdr_conf" 'ctrl+k' "herdr: 解放した ctrl+k が残っていない"


# --- Neovim ----------------------------------------------------------------
nvim_keymaps="$(cat "$CHEZMOI_SOURCE/private_dot_config/nvim/lua/config/keymaps.lua")"

for k in h j k l; do
  assert_contains "$nvim_keymaps" "\"<C-w>$k\"" "nvim: <C-w>$k がナビゲーションに割り当てられている"
done
assert_not_contains "$nvim_keymaps" '"<C-h>", navigate' "nvim: herdr に奪われる <C-h> を使っていない"
assert_not_contains "$nvim_keymaps" '"<C-l>", navigate' "nvim: herdr に奪われる <C-l> を使っていない"
assert_not_contains "$nvim_keymaps" 'vim-herdr-navigation' "nvim: 無効化したプラグインへの言及が無い"


# --- ドキュメントと設定の整合 -----------------------------------------------
doc="$(cat "$CHEZMOI_SOURCE/private_dot_config/docs/keybindings.md")"

# 対象 6 ツールの節がある。
for tool in "skhd" "Ghostty" "Herdr" "Neovim" "zsh" "lazygit"; do
  assert_contains "$doc" "## $tool" "docs: $tool の節がある"
done

# 使っていないツールは載せない。
assert_not_contains "$doc" "OmniWM" "docs: 不使用の OmniWM が載っていない"

# 今回変えたキーが載っている。
assert_contains "$doc" "Ctrl-h" "docs: タブ移動の Ctrl-h が載っている"
assert_contains "$doc" "Ctrl-l" "docs: タブ移動の Ctrl-l が載っている"
assert_contains "$doc" "Ctrl-q" "docs: pane close の Ctrl-q が載っている"
assert_contains "$doc" "C-w" "docs: Neovim の <C-w> ナビゲーションが載っている"
assert_contains "$doc" "Alt-w" "docs: workspace picker の Alt-w が載っている"

# herdr の起動ショートカット節だけを切り出して検査する。Alt-f / Alt-n / Alt-r /
# Alt-y は skhd 側では実在するキーなので、doc 全体を対象にすると誤検出になる。
launch="$(printf '%s\n' "$doc" | sed -n '/^### 起動ショートカット/,/^### prefix 経由/p')"

# config.toml にある起動キーが漏れていない。
for k in "Alt-g" "Alt-e" "Alt-c" "Alt-a" "Alt-z" "Alt-t"; do
  assert_contains "$launch" "\`$k\`" "docs: 起動キー $k が載っている"
done

# config.toml に無いキーを起動ショートカットとして載せない。
# Alt-Space / Alt-f / Alt-n / Alt-r は旧 tmux 由来、Alt-y は今回削除したもの。
for k in "Alt-Space" "Alt-f" "Alt-n" "Alt-r" "Alt-y"; do
  assert_not_contains "$launch" "\`$k\`" "docs: 起動ショートカットに実装外の $k が載っていない"
done

# 参照先の設定ファイルパスが書かれている。
for p in "herdr/config.toml" "skhd/skhdrc" "ghostty/config" "nvim/lua/config/keymaps.lua"; do
  assert_contains "$doc" "$p" "docs: $p への参照がある"
done


# --- README / CLAUDE.md からの導線 --------------------------------------------
readme="$(cat "$CHEZMOI_SOURCE/README.md")"
claude_md="$(cat "$CHEZMOI_SOURCE/CLAUDE.md")"

assert_contains "$readme" "private_dot_config/docs/keybindings.md" "README: キーバインド一覧へのリンクがある"
assert_contains "$readme" "herdr" "README: Main Tools に herdr がある"
assert_not_contains "$readme" "tmux/tmux" "README: 使っていない tmux が Main Tools に無い"
assert_not_contains "$readme" "OmniWM" "README: 使っていない OmniWM が Main Tools に無い"
assert_contains "$claude_md" "private_dot_config/docs/keybindings.md" "CLAUDE.md: キーバインド一覧の場所が書いてある"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
