# Dotfiles

## Setup

```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply cellfusion
```

これ 1 本で chezmoi が入り、リポジトリが clone され、`chezmoi apply` まで走る。
init 時に yabai / skhd / SketchyBar を環境ごとに個別に選ぶ（既定はすべて使用）。
選ばなかったツールはインストール・設定配布・サービス登録を行わない。
SketchyBar を使い yabai を使わない場合は、Homebrew のサービスとして起動する。
既に導入済みのツールやサービスは選択を変更しても自動削除・停止されない。
apply の中で Homebrew の導入、Brewfile の適用、ランタイムの導入、AI CLI の導入、
選択時のみ SketchyBar helper のビルド、選択したサービスの登録が順に実行される。

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
| Review | Tuicr | Interactive diff review |
| Worktrees | [Worktrunk](https://worktrunk.dev/) | Invisible write isolation for child tasks |
| Finder | [television](https://github.com/alexpasmantier/television) | Fuzzy finder (tv) |
| Window Manager | [yabai](https://github.com/koekeishiya/yabai) + [skhd](https://github.com/koekeishiya/skhd) | Tiling window manager + hotkey daemon (macOS) |
| AI | OMP / [Claude Code](https://claude.ai/code) / Codex | OMP-first development; independent agents in Herdr panes |
| Bar | [SketchyBar](https://github.com/FelixKratz/SketchyBar) | Custom menu bar (macOS) |
| Japanese Input | [AquaSKK](https://github.com/codefirst/aquaskk) | SKK input method |

メイン作業とPRレビューはHerdrの専用worktree＋workspaceで実行する。
通常の委譲はOMP内、書き込み分離だけが必要な子作業はWorktrunkで作り、Herdrには表示しない。
subMBPは`herdr --remote`でmainMBP側へ接続する。Android端末にはMoshiを使う。

OMP のデフォルト設定は `private_dot_omp/agent/private_config.yml` から
`~/.omp/agent/config.yml` へ共有する。環境別 profile、認証、履歴、DB は共有しない。
通常の `omp` 起動は Claude／Codex の環境切替から独立している。

## Documentation

- [Keybindings Cheat Sheet](private_dot_config/docs/keybindings.md) —
  skhd / Ghostty / Herdr / Neovim / zsh / lazygit のキーバインド一覧。
  層をまたいで奪われるキーもここにまとめてある。
  `chezmoi apply` 後は `~/.config/docs/keybindings.md` から引ける。
- [Tool Inventory](private_dot_config/docs/tools.md) —
  使っているツールの一覧と導入経路、削除候補。
  `chezmoi apply` 後は `~/.config/docs/tools.md` から引ける。
