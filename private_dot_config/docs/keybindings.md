# Keybindings Cheat Sheet

このリポジトリで設定しているキーバインドの一覧。chezmoi ソース側のパスを各節に
書いてあるので、変更するときはそこを編集する。

## キーの優先順位

同じ物理キーは上の層から順に取られる。上の層が取ったキーは下の層に届かない。

| 層 | 何が取るか | 設定ファイル |
|-----|-----------|-------------|
| 1. システム | skhd（yabai のホットキー） | `skhd/skhdrc` |
| 2. 端末 | Ghostty | `ghostty/config` |
| 3. 多重化 | Herdr | `herdr/config.toml` |
| 4. pane 内 | Neovim / zsh / lazygit | 各ツールの設定 |

たとえば `Alt-y` は skhd が取るので Herdr には届かない。`Ctrl-l` は Herdr が取るので
pane 内の zsh には届かない。

---

## skhd + yabai (Window Manager)

タイル型ウィンドウマネージャ。Config: `skhd/skhdrc`（キー） / `yabai/executable_yabairc`（レイアウト）。

`Alt` は macOS の Option キー。skhd はシステムレベルで受け取るため、ここに挙げた
キーは端末にもアプリにも届かない。

### フォーカスとウィンドウ移動

| Key | Action |
|-----|--------|
| `Alt-h/j/k/l` | ウィンドウのフォーカスを左/下/上/右へ |
| `Alt-Shift-h/j/k/l` | ウィンドウを入れ替える（swap） |
| `Alt-Shift-Ctrl-h/j/k/l` | 分割ツリー内で付け替える（warp） |
| `Alt-Ctrl-h` / `Alt-Ctrl-l` | モニタ間でフォーカスを移す |

### リサイズとレイアウト

| Key | Action |
|-----|--------|
| `Alt-,` / `Alt-.` | 幅を縮める / 広げる |
| `Alt-Shift-,` / `Alt-Shift-.` | 高さを縮める / 広げる |
| `Alt-Shift-0` | 分割を均等に戻す |
| `Alt-r` / `Alt-Shift-r` | 分割ツリーを 90 度 / 270 度回転 |
| `Alt-x` / `Alt-y` | x 軸 / y 軸でミラー |
| `Alt-v` / `Alt-s` / `Alt-q` | 次のウィンドウの分割方向を右 / 下 / スタックに |
| `Alt-p` / `Alt-n` | スタック内の前 / 次のウィンドウ |
| `Alt-f` | スペース内で最大化（zoom-fullscreen） |
| `Alt-m` | 親ノードいっぱいに広げる（zoom-parent） |
| `Alt-Shift-f` | フロート切替 |
| `Alt-Shift-c` | フロートにして中央寄せ |
| `Alt-Shift-/` | スペースのレイアウトを bsp / float で切替 |

### スペース

| Key | Action |
|-----|--------|
| `Alt-1`..`Alt-9` | スペース 1-9 へ移動 |
| `Alt-Shift-1`..`Alt-Shift-9` | ウィンドウをスペース n へ移動（フォーカスも追従） |

### その他

| Key | Action |
|-----|--------|
| `Alt-Shift-;` | yabai と skhd を再起動 |

---

## Ghostty (Terminal)

Config: `ghostty/config`。

| 設定 | 効果 |
|------|------|
| `macos-option-as-alt = true` | Option を Alt として送る（skhd / Herdr の Alt キーが届くようになる） |
| `keybind = ctrl+tab=unbind` | Ghostty 自身のタブ切替を無効化 |
| `keybind = ctrl+shift+tab=unbind` | 同上（逆方向） |

タブ管理は Herdr に任せるため、Ghostty のタブ機能は使わない。

---

## Herdr (Multiplexer)

AI エージェント向けの多重化ツール。prefix は `Ctrl-b`。
Config: `herdr/config.toml`（`chezmoi apply` 後に `herdr server reload-config` で反映）。

`[keys]` でアクションにキーを割り当てると、そのアクションのデフォルトキーは**置換され**、
元のキーでは呼べなくなる。下の表に載せているのは実際に有効なキーだけ。

### prefix なしの直接キー

| Key | Action |
|-----|--------|
| `Ctrl-h` / `Ctrl-l` | 前 / 次のタブ |
| `Alt-w` | workspace picker を開く |
| `Ctrl-t` | 新しいタブ |
| `Ctrl-n` | 新しい workspace |
| `Ctrl-i` | サイドバーの表示切替 |
| `Ctrl-q` | pane を閉じる（確認プロンプトあり） |

`Alt-w` の picker（herdr の workspace navigation surface）の中では、`↑` / `↓` が
workspace を、`h` / `j` / `k` / `l` が pane を選ぶ。modifier を使わないので pane 内の
アプリとは衝突しない。

`Ctrl-q` は herdr-confirm-close-pane プラグイン経由。`Close this pane? (y/n):` が出て、
`y` で閉じ、それ以外のキーと Esc で取り消す。ビルトインの `close_pane` は無効化してあるので
`prefix+x` では閉じない。

### 起動ショートカット（prefix なし）

| Key | Action |
|-----|--------|
| `Alt-g` | lazygit（popup、全画面） |
| `Alt-e` | ファイル選択 → `$EDITOR`（`tv edit`） |
| `Alt-c` | Claude Code を新しいタブで起動（claude を持たない環境では起動しない） |
| `Alt-a` | agent-launcher（`tv agent-launcher`） |
| `Alt-z` | ディレクトリ移動（`tv zoxide`） |
| `Alt-t` | スクラッチ端末（popup、80%） |

これらのキーは skhd が取る Alt キー（`h/j/k/l/r/x/y/v/s/q/p/n/f/m`、`1-9`、`,`、`.`）を
避けてある。新しく足すときも同じ制約が掛かる。

### prefix 経由（`Ctrl-b` → キー）

| Key | Action |
|-----|--------|
| `h/j/k/l` | pane のフォーカスを移す |
| `Shift-h/j/k/l` | pane を入れ替える |
| `v` / `-` | 右に分割 / 下に分割 |
| `z` | pane をズーム |
| `r` | リサイズモード |
| `[` | コピーモード |
| `t` | git worktree を作る |
| `1`..`9` | タブ 1-9 へ |
| `Shift-T` | タブ名を変更 |
| `Shift-X` | タブを閉じる |
| `Shift-W` | workspace 名を変更 |
| `Shift-D` | workspace を閉じる |
| `g` | Goto ピッカー（エージェント一覧を含む） |
| `Alt-1`..`Alt-9` | エージェント行 n にフォーカス |
| `q` | セッションからデタッチ |
| `?` | 有効なバインドを一覧表示 |

`c`（new tab）/ `n` `p`（タブ移動）/ `b`（サイドバー）/ `Shift-N`（new workspace）/
`w`（workspace picker）/ `x`（close pane）は直接キーに置き換えたので、prefix 経由では
効かない。

### プラグイン

`plugins.json` は chezmoi の管理外なので、新しいマシンでは手で入れ直す。

```bash
herdr plugin install poweroutlet2/herdr-confirm-close-pane
herdr plugin disable vim-herdr-navigation
```

vim-herdr-navigation は `Ctrl-h/j/k/l` を前提にしたプラグインだが、`Ctrl-h` と
`Ctrl-l` がタブ移動で埋まっているため無効化してある。

---

## Neovim

LazyVim ベース。Config: `nvim/lua/config/keymaps.lua`。

### pane / split ナビゲーション

| Key | Mode | Action |
|-----|------|--------|
| `<C-w>h/j/k/l` | Normal | split 間を移動。split の端では隣の Herdr pane へ越境する |

LazyVim 標準の `<C-w>h/j/k/l`（split 移動のみ）を上書きしている。
素の `<C-h>` / `<C-l>` は Herdr が取るので Neovim には届かない。`<C-j>` / `<C-k>` は
Herdr の割り当てを外したので Neovim に届く（snacks.picker の上下移動で使う）。

### カスタムキーマップ

| Key | Mode | Action |
|-----|------|--------|
| `jj` | Insert | インサートモードを抜ける |

### LazyVim の頻用キー

| Key | Mode | Action |
|-----|------|--------|
| `<leader>` | Normal | Space |
| `<leader><space>` | Normal | ファイル検索 |
| `<leader>ff` | Normal | ファイル検索（root） |
| `<leader>sg` | Normal | grep（root） |
| `<leader>e` | Normal | エクスプローラ |
| `<leader>gg` | Normal | gitui |
| `<leader>xx` | Normal | 診断一覧 |
| `<leader>ca` | Normal | コードアクション |
| `<leader>cr` | Normal | リネーム |
| `gd` | Normal | 定義へジャンプ |
| `gr` | Normal | 参照一覧 |
| `K` | Normal | ホバードキュメント |
| `]d` / `[d` | Normal | 次 / 前の診断 |
| `]b` / `[b` | Normal | 次 / 前のバッファ |
| `S-h` / `S-l` | Normal | 前 / 次のバッファ |

網羅ではない。全部見るときは Neovim 内で `<leader>sk`（キーマップ検索）を使う。

---

## zsh

Config: `zsh/dot_zshrc`。**`bindkey` によるカスタマイズは無い。すべて zsh のデフォルト。**

デフォルトのうち Herdr に奪われて届かないもの。

| Key | 本来の動作 | 代替 |
|-----|-----------|------|
| `Ctrl-l` | clear-screen | `clear` コマンド |
| `Ctrl-q` | push-line | なし |
| `Ctrl-h` | backward-delete-char | `Backspace` |
| `Ctrl-t` | transpose-chars | なし |
| `Ctrl-n` | down-line-or-history | `↓` |
| `Ctrl-i` | expand-or-complete | `Tab` |
| `Alt-w` | copy-region-as-kill | なし |

---

## lazygit

Config: `lazygit/config.yml`。**キーバインドのカスタマイズは無い。すべて lazygit のデフォルト。**

`config.yml` で設定しているのはログの表示形式（`branchLogCmd` / `allBranchesLogCmds`）だけ。
キー一覧は lazygit 内で `?` を押して見る。

---

## 既知の衝突と占有

層をまたいで奪われるキー。

| Key | 取る層 | 届かなくなる先 |
|-----|--------|--------------|
| `Alt-h/j/k/l` ほか Alt 系 | skhd | Ghostty / Herdr / pane 内すべて |
| `Ctrl-h` / `Ctrl-l` | Herdr（タブ移動） | Neovim の `<C-h>` `<C-l>`、zsh の backward-delete-char / clear-screen |
| `Alt-w` | Herdr（workspace picker） | zsh の copy-region-as-kill |
| `Ctrl-t` / `Ctrl-n` / `Ctrl-i` / `Ctrl-q` | Herdr | zsh の transpose-chars / down-line-or-history / expand-or-complete / push-line |
| `Ctrl-Tab` / `Ctrl-Shift-Tab` | Ghostty が unbind | 誰にも届かない（意図的） |

---

## メンテナンス手順

キーバインドを変えたらこのファイルも更新する。

1. chezmoi ソース側の設定ファイルを編集する（`~/.config` を直接触らない）
2. `bash tests/test-keybindings.sh` でドキュメントと設定の整合を確認する
3. `chezmoi apply`
4. Herdr の設定を変えた場合は `herdr server reload-config`
5. skhd の設定を変えた場合は `skhd --restart-service`（`Alt-Shift-;` でも可）

herdr のプラグインは chezmoi の管理外にある。新しいマシンでは上記とは別に
`herdr plugin install` / `herdr plugin disable` を打つ必要がある（Herdr の節を参照）。
