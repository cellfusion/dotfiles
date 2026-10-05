# worktree — Herdr・OMP・Worktrunkの分担

| 用途 | 管理 | Herdrへの表示 |
|---|---|---|
| メインエージェントの作業隔離 | defaultブランチからHerdrでworktreeを作成 | 専用workspace |
| PRレビュー | PRのbaseコミットからHerdrでworktreeを作成 | 専用workspace、root paneでOMP |
| 子作業の書き込み分離 | Worktrunk (`wt`) | workspace・tab・paneを追加しない |

通常の委譲はOMP内で済ませる。ユーザーが確認・介入したい作業、独立した対話、
別CLIエージェントの実行にはHerdrの別paneを使う。**別paneと別worktreeは独立した判断**であり、
書き込み分離だけを理由にpaneを増やさない。

## メイン作業

リポジトリのdefaultブランチを確認し、解決したコミットを起点に作る。
作業中のpaneを保持する場合は`--no-focus`を付ける。

```sh
herdr worktree create --cwd /path/to/repo --branch feat/example \
  --base <default-commit> --label example --no-focus
```

応答のworktree path、workspace ID、root pane IDを使う。IDを推測しない。
既に適切な隔離worktree内なら、もう一つ作らない。

## 非表示の子worktree

`worktrunk/config.toml`は置き場所だけを設定する。Herdrへの自動open／closeフックは置かない。

```toml
worktree-path = "~/.herdr/worktrees/{{ repo }}/{{ branch | sanitize }}"
```

子へ必要な前提が含まれる親の確定コミットから分岐する。

```sh
wt -C /path/to/repo switch --create child/example --base <parent-commit> \
  --no-cd --no-hooks --format json
```

返されたJSONの`path`を子のcwdとして渡す。親のcwdは変えず、Herdrには開かない。
`--no-hooks`によりプロジェクトのフックも実行しない。依存セットアップが必要なら、
信頼済みの手順を別途明示的に実行する。

未コミット変更、`.env`、認証情報、履歴を自動コピーしない。
子に必要な未コミット前提があれば、委譲開始前にその扱いを決める。
成果はメイン作業ブランチへ取り込み、defaultへ自動mergeしない。

MADで台帳を使う場合は`mad-worktree`がWorktrunkを呼び、path・branch・base・所有権・
親checkoutの正規pathとブランチ・統合状態を記録する。親は名前付きブランチである必要がある。
削除時も同じ管理経路を使い、記録した親checkoutとブランチへ戻ってから実行する。
別checkoutや、親のブランチを切り替えた状態では削除しない。
統合済みの判定には記録した親ブランチを使う。

## PRレビュー

Herdr内のリポジトリから次を実行する。

```sh
pr-review 123
pr-review https://github.com/owner/repo/pull/123 --quick
```

番号は現在のリポジトリに属するPRを指す。URLとローカルリポジトリが一致しなければ、
環境作成前に停止する。PRのbase/headを固定し、base側でOMPを起動する。
PR headの指示ファイルを起動時に読み込ませないためである。

レビュー用worktreeとworkspaceを作り、既存root paneでOMPと`pr-review`スキルを開始する。
準備済み環境内では追加worktreeやOMPを作らない。
OMPから委譲するときは`--no-focus`を付ける。

結果と環境は確認・追加質問用に残す。投稿や終了だけを理由に自動削除しない。
GitHubへの投稿は明示確認後に行う。起動失敗、timeout、blocked、unknownは完了ではなく、
環境を保持して原因を確認する。

## 所有権と終了

作成時に管理者（Herdr／Worktrunk／external）、絶対path、branch、base SHA、
workspace/pane IDがあればそのID、統合状態を記録する。

- Herdrで作ったworktreeはHerdr経路で終了する。
- Worktrunkで作った子worktreeはWorktrunk経路で終了する。
- 既存・外部所有のworktreeは削除しない。
- 実行中、未保存、未統合、保留、所有権不明の場合は保持する。
- force／clobberを標準にしない。ブランチ削除は別判断にする。

`wt remove`は既定でブランチも削除し得るため、保持する場合は`--no-delete-branch`を付ける。
自動化では`--no-hooks --foreground --format json`を使う。

## 成果物

設計・実装計画・レビュー資料の保存先は
`~/.agents/skills/_shared/scripts/agent-docs-dir`で解決する。
`~/docs/<owner>/<repo>/`を同じリポジトリの全worktreeで共有する。
認証情報や生の会話を台帳・監査ログへ保存しない。

PRレビューの実行情報と成果物は`pr-review`が作る私有runディレクトリに保存する。
worktreeやworkspaceを閉じても成果物は残す。

## Chezmoiの変更

`chezmoi apply`が読むのは`chezmoi source-path`の正本であり、隔離worktreeではない。
実装・検証後、承認した変更だけを正本へ統合する。
対象限定のdiffを確認し、明示許可を得てからapplyする。
既存のユーザー変更や認証情報は取り込まない。
