# Dotfiles

## Setup

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply cellfusion
```

これ 1 本で chezmoi が入り、リポジトリが clone され、`chezmoi apply` まで走る。
apply の中で Homebrew の導入、Brewfile の適用、ランタイムの導入、AI CLI の導入、
sketchybar helper のビルド、yabai と skhd のサービス登録が順に実行される。

Homebrew の導入と cask のインストールで、sudo のパスワードを複数回聞かれる。

apply のあとに手でやることが 4 つある。手順は
[Tool Inventory](private_dot_config/docs/tools.md) の「apply 後に手でやること」にある。

マニフェストを手で回すこともできる。実行するのはインストールだけで、既に入っている
ものの upgrade は行わない。

```bash
brew bundle --file ~/.config/install/Brewfile --no-upgrade
```

## Main Tools

| Category | Tool | Description |
|----------|------|-------------|
| Dotfiles | [chezmoi](https://github.com/twpayne/chezmoi) | Dotfiles manager |
| Terminal | [Ghostty](https://ghostty.org/) | Primary terminal |
| Multiplexer | [Herdr](https://herdr.dev/) | Terminal multiplexer for coding agents |
| Editor | [Neovim](https://neovim.io/) (LazyVim) | Primary editor |
| Git | [lazygit](https://github.com/jesseduffield/lazygit) | Terminal UI for git |
| Finder | [television](https://github.com/alexpasmantier/television) | Fuzzy finder (tv) |
| Window Manager | [yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/koekeishiya/skhd) | Tiling window manager + hotkey daemon (macOS) |
| AI | [Claude Code](https://claude.ai/code) | AI coding assistant |
| Bar | [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Custom menu bar (macOS) |
| Japanese Input | [AquaSKK](https://github.com/codefirst/aquaskk) | SKK input method |

## Documentation

- [Keybindings Cheat Sheet](private_dot_config/docs/keybindings.md) —
  skhd / Ghostty / Herdr / Neovim / zsh / lazygit のキーバインド一覧。
  層をまたいで奪われるキーもここにまとめてある。
  `chezmoi apply` 後は `~/.config/docs/keybindings.md` から引ける。
- [Tool Inventory](private_dot_config/docs/tools.md) —
  使っているツールの一覧と導入経路、削除候補。
  `chezmoi apply` 後は `~/.config/docs/tools.md` から引ける。
