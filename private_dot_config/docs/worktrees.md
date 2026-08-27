# git worktree — herdr と worktrunk の分担

worktree まわりは 2 つのツールで分担している。

| ツール | 担当 |
|---|---|
| herdr | worktree に紐づく workspace（端末）。人間が入って中の作業を見る |
| worktrunk (`wt`) | worktree の置き場所、追跡外ファイルのコピー、依存インストール |

両者が同じパスを指すように、worktrunk 側のテンプレートを herdr のレイアウトに
合わせてある。設定は `worktrunk/config.toml`（chezmoi ソース:
`private_dot_config/worktrunk/config.toml`）。

    worktree-path = "~/.herdr/worktrees/{{ repo }}/{{ branch | sanitize }}"

herdr も worktrunk もブランチ名のスラッシュをダッシュに置換するので、
`feat/foo` はどちらから作っても `~/.herdr/worktrees/<repo>/feat-foo` になる。

user config には herdr との接続だけを置いている。

- `post-start` — 作られた worktree を `herdr worktree open` で workspace として開く
- `pre-remove` — `wt remove` の前に対応する workspace を `herdr workspace close` で閉じる

`herdr` の CLI は socket 経由なので、herdr の pane の外（背後で走る post- フック）
からでも届く。

## リポジトリ側に置くもの

worktree ごとのセットアップはリポジトリ側の 2 ファイルで決まる。どちらもコミットする。

`.worktreeinclude` — コピーする追跡外ファイル。gitignore 構文で書く。
git の機能ではなく worktrunk が読むファイルで、「gitignore されていて、かつここに
書いてある」ものだけがコピー対象になる。

    .env*
    node_modules/

`.config/wt.toml` — セットアップの手順。

    [[pre-start]]
    copy = "wt step copy-ignored --require-include"

    [[pre-start]]
    install = "npm ci"

`[[pre-start]]` を 2 つ並べると順に走る。1 つの `[pre-start]` テーブルに 2 つ
書くと同時に走るので、コピーとインストールの順序が壊れる。

**`pre-` を使う。** `post-` は背後で走って即座に戻るため、直後にテストを回す
使い方（agent の worktree セットアップ）では未完了の作業ツリーに当たる。
dev server のような常駐プロセスだけ `post-start` に置く。

`--require-include` を付けると `.worktreeinclude` の無いリポジトリでは何もコピー
しない。付けないと gitignore されているものが全部コピーされる。

コピーは reflink（APFS の copy-on-write）なので、`node_modules` や `target/` でも
実質ゼロコストで済む。

## 使い方

人間:

    wt switch -c feat/foo    # worktree 作成 → セットアップ → herdr workspace が開く
    wt list
    wt merge
    wt remove feat/foo

エージェント: SDD の task worktree は `wt switch --create <branch> --base <base> --no-cd
--format json -y --config ~/.config/worktrunk/agent.toml` で作る。作成は `sdd-run` が
`task-worktree` 経由で行い、herdr には登録しない。worktree は
`~/.local/state/sdd/worktrees/` に置かれる。.env のコピーと依存インストールは
agent.toml の `pre-start` フックが同期で行うので、`wt hook pre-start` を別途叩かない。

- claude の workspace trust は cwd の祖先から継承される。`~/.local/state/sdd/worktrees`
  を 1 度 trust すれば、以後すべての task worktree でダイアログは出ない。trust の記録は
  `CLAUDE_CONFIG_DIR`（この環境では `~/.config/claude`）側の `.claude.json` にある。

片付けは `wt remove --no-delete-branch` → `git branch -d` の順で行う。

`wt hook <type>` は worktree を誰が作ったかを問わず動く。手順は
`using-git-worktrees` と `subagent-driven-development` のスキルに書いてある。

## 注意点

- `worktree-path` は user config 専用で、リポジトリ側の `.config/wt.toml` には
  書けない。マシンごとの設定になる
- agent worktree は人用 config では見えない。`wt` には
  `--config ~/.config/worktrunk/agent.toml` を渡す
- user config のフックとリポジトリ側のフックは**並行に走る**。順序が要る処理は
  同じファイルの中で `[[...]]` を並べる
- `wt step relocate` は worktree を worktrunk の想定パスへ移動する。herdr の
  workspace とパスがずれるので使わない
- `herdr worktree open` はリポジトリの文脈が要る。`--path` だけでは
  `worktree_not_found` になるので `--cwd <main worktree>` を併せて渡す
