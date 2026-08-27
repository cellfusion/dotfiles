## braid の呼び方

braid は複数のエージェントを組み合わせたフローを記述・実行・観測する CLI である。この節は
braid を呼ぶすべてのスキルが共有する。

### 前提

`braid` が PATH にあること。無ければインストール済みと仮定して続行せず、実行方法が無いことを
報告して止まる。

```bash
command -v braid
```

cwd が git リポジトリの中であること。codex に振られた役割は git 管理外の作業ディレクトリでは
必ず失敗する。braid はこれを静的検証で落とさないので、呼ぶ側が確かめる。

```bash
git rev-parse --is-inside-work-tree
```

### 手順

**1. 本実行の前に dry-run を通す。**

```bash
braid run RECIPE --arg k=v --dry-run --json
```

引数の不足、役割・スキーマ・プロンプトの欠落、参照先の不在はここで全件返る。失敗したら本実行へ
進まず、出力をそのまま報告する。

**2. 本実行する。同期で待つ。**

```bash
braid run RECIPE --arg k=v
```

時間のかかるプロセスを別 pane へ委譲する規約の例外にする。braid は run store と `run.lock` で
状態を持ち、プロセスが死ねば OS がロックを解放するので孤児 run が残らない。停止は
`braid cancel`、進行の目視は TUI でできる。

ノード 1 つあたりの既定の実行上限は 1200 秒で、`--timeout <秒>` で全ノード共通に変えられる。
`review` はノード 4 つ、`implement` / `waves` はレビューループを回すため、シェル実行ツール側の
コマンドタイムアウトが既定より短いなら明示的に伸ばす。伸ばしても足りない見込みなら
`--detach` を付けて runId だけを受け取り、`braid status <runId>` で進行を追う。

### 引数

すべて文字列で渡す。`requirements` / `review_file` / `spec_dir` のようにファイルを指す引数も、
パスの文字列としてプロンプトへ埋め込まれる。読むのは役割エージェントである。

役割エージェントが読める範囲は cwd に縛られる。claude の read 役は `--setting-sources ""` で
`permissions.allow` を失うため、cwd の外を 1 つも読めない。braid が `--add-dir` を渡すのは
`review_loop` が作る diff パッケージのディレクトリだけで、`--arg` で渡したパスには渡さない。
隔離しないノードの cwd は `braid run` を打った場所である。したがって **`--arg` で渡すパスは
実行時の cwd の下にあること**。cwd の外のパスを渡しても braid はエラーにせず、役割エージェントが
読めずに劣化した結果を返すだけなので気づきにくい。

配列は JSON string array で渡す。

```bash
braid run research --arg topic=... --arg perspectives='["現状","制約","代替案"]'
```

### 出力

成功すると最終ノードの構造化出力が pretty JSON で stdout に出る。

失敗すると終了コードが非ゼロになる。`--json` を付ければ
`{"runId": ..., "error": {"nodeId": ..., "message": ...}}` が stdout に出る。付けなければ
stderr にメッセージが出る。

### 失敗したとき

**リトライしない。** スキーマ違反も commit 検査の失敗も、同じ条件の再試行は同じ結果になる。
`braid status <runId>` の内容と、worktree および呼び出し元ブランチに残ったコミットの有無を
報告する。片付けは利用者が行う。

### run を追う

```bash
braid ls                # 一覧
braid status RUN_ID     # 1 つの詳細
braid                   # TUI（サブコマンド無しで起動する）
```
