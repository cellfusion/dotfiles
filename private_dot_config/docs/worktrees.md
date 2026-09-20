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

エージェント: `multi-agent-development` の `implement` と `spike` では、worktree を作るのは親である。
`mcp__paseo__create_agent` は作成時に `workspaceId` を要求するので、子を起動する前に workspace が
存在している必要がある。親は台帳の `path` から diff を取るので、子が別の場所に worktree を作ると
親が取る diff が空になる。worktree を作るのは `mad-worktree` であり、素の `git worktree add` を使う。
置き場所は `${MAD_STATE_DIR}/worktrees/<repo-name>/<branch-slug>` で、`MAD_STATE_DIR` の既定値は
`~/.local/state/mad` である。Paseo MCP backend では、作成済みの worktree の絶対パスを
`mcp__paseo__create_workspace` の `path` に渡し `isolation` `local` で呼ぶ。Paseo は worktree を
作らず、既にある checkout に workspace を取り付けるだけである。どちらも herdr には登録しない。
子は親が渡した worktree の中で働く。

追跡外ファイルのコピーと依存インストールは、リポジトリに `.config/wt.toml` があるときだけ
`wt hook pre-start` が行う。`mad-worktree` は worktree を作った後にそのフックを 1 度呼ぶ。
`wt` が入っていないときと `.config/wt.toml` が無いときは何もしない。

- claude の workspace trust は cwd の祖先から継承される。`${MAD_STATE_DIR}/worktrees`
  を 1 度 trust すれば、以後すべての MAD の worktree でダイアログは出ない。trust の記録は
  `CLAUDE_CONFIG_DIR`（この環境では `~/.config/claude`）側の `.claude.json` にある。

片付けは `mad-worktree remove --branch <branch>` で行う。ブランチも消すときだけ
`--delete-branch` を足す。`mad-worktree` は `git branch -d` しか呼ばないので、取り込んでいない
ブランチの削除は git が失敗させる。

`wt hook <type>` は worktree を誰が作ったかを問わず動く。worktree の作成・統合・後始末の手順は
`using-git-worktrees` スキルにある。`implement` recipe の親はこの規約に従う。

## エージェントの成果物の置き場所

spec・実装プラン・SDD の作業物・レビュー package は
`~/docs/<owner>/<repo>/` に置く。パスは
`~/.agents/skills/_shared/scripts/agent-docs-dir` が返す。

| サブディレクトリ | 置くもの |
|---|---|
| `specs/` | architectural な設計で作成する spec |
| `plans/` | writing-plans が書く実装プラン |
| `sdd/<plan-basename>/` | SDD の ledger・brief・report・review package |
| `reviews/` | SDD 外の単発レビュー package |

MAD の run ディレクトリは成果物ではなく実行時の状態なので、`~/docs/<owner>/<repo>/` には置かない。
置き場所は `${MAD_STATE_DIR}/runs/<run-id>/` であり、`mad-progress list` はそこだけを走査する。

`<owner>/<repo>` は本体チェックアウトの remote の URL から決まる。remote が 1 つも無ければ
本体チェックアウトの絶対パスの末尾 2 要素を使う。worktree から呼んでも本体チェックアウトから
呼んでも同じパスになるので、**成果物は同じリポジトリのすべての worktree で共有される**。
リポジトリの作業ツリーの外にあるため、作業ツリーを掃除しても worktree を消しても残る。

レビュー役の子は現在の作業ディレクトリの外を読めない engine 設定でも動く必要がある。子へ渡す
review package と要件ファイルは、渡す直前に `<repo-root>/.agent-review/` へ複製し、複製先の
絶対パスを渡す。実行ごとの staging directory `<repo-root>/.agent-review/run.XXXXXX/` だけを
レビューの終了後に削除し、`.agent-review/` とその `.gitignore` は残す。global gitignore と
自己無視の `.gitignore` の 2 段で無視される。

MAD の worktree（`${MAD_STATE_DIR}/worktrees/`）とは別系統である。MAD の worktree の置き場所は
`mad-worktree` が決める。

## 注意点

- `worktree-path` は user config 専用で、リポジトリ側の `.config/wt.toml` には
  書けない。マシンごとの設定になる
- user config のフックとリポジトリ側のフックは**並行に走る**。順序が要る処理は
  同じファイルの中で `[[...]]` を並べる
- `wt step relocate` は worktree を worktrunk の想定パスへ移動する。herdr の
  workspace とパスがずれるので使わない
- `herdr worktree open` はリポジトリの文脈が要る。`--path` だけでは
  `worktree_not_found` になるので `--cwd <main worktree>` を併せて渡す
