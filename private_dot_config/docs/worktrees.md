# worktree — 実行環境とcheckout所有権

| 用途 | 管理 | 表示 |
|---|---|---|
| メインエージェントの作業隔離 | 既存checkoutの所有者を確認し、必要ならWorktrunk (`wt`) | 表示は必要に応じて別途判断 |
| PRレビュー | 対応する選択環境のadapterで固定PR base SHAから隔離checkoutを作成 | 旧HerdrまたはOrcaの専用OMP |
| 子作業の書き込み分離 | Worktrunk (`wt`) | space・tab・paneを追加しない |

同一repositoryの通常の委譲は実行ハーネス内で済ませる。独立した対話や別CLIは
herdr-core (`hc`) のterminalで実行でき、表示は不要である。ユーザーが表示・介入を
求めたときだけherdr-appを使う。**terminal、表示pane、worktreeの作成と所有権は別の判断**
であり、書き込み分離だけを理由にpaneを増やさない。

## メイン作業

既に適切な隔離worktree内なら、もう一つ作らない。新規に必要な場合はリポジトリの
defaultブランチを確認し、解決したコミットを起点にWorktrunkで作る。

```sh
wt -C /path/to/repo switch --create feat/example --base <default-commit> --no-cd --format json
```

返されたJSONの `path` を作業cwdにし、checkout ownerはWorktrunkとして記録する。
hcのterminalはcheckoutの所有者にならない。旧Herdrで表示する場合は、そのpathを開く。

```sh
herdr worktree open --cwd /path/to/repo --path <returned-path> --label example --no-focus
```
こちらは返されたworktree path、旧workspace ID、root pane IDを記録する。IDを推測せず、
hcのterminal addressやherdr-appのpane IDとして使わない。

## 非表示の子worktree

共通の新規worktreeは `~/worktrees/<メインcheckoutの絶対path>/<branch>` に置く。
branchの `/` はディレクトリ区切りとして保持し、同名cloneや `feat/a` と `feat-a` の衝突を避ける。
設定変更前に作成されたworktreeは移動しない。Herdrへの自動open／closeフックは置かない。

子へ必要な前提が含まれる親の確定コミットから分岐する。

```sh
wt -C /path/to/repo switch --create child/example --base <parent-commit> \
  --no-cd --format json
```

返されたJSONの `path` を子のcwdとして渡す。親のcwdは変えず、Herdrには開かない。
共通コピー・個人のリポジトリ設定・承認済みproject hookが実行される。
コピー対象に秘密情報を含めると子worktreeにも配置されるため、`.worktreeinclude` は慎重に選ぶ。
子に必要な未コミット前提があれば、委譲開始前にその扱いを決める。
成果はメイン作業ブランチへ取り込み、defaultへ自動mergeしない。

MADで台帳を使う場合は`mad-worktree`がWorktrunkを呼び、path・branch・base・所有権・
親checkoutの正規pathとブランチ・統合状態を記録する。親は名前付きブランチである必要がある。
削除時も同じ管理経路を使い、記録した親checkoutとブランチへ戻ってから実行する。
別checkoutや、親のブランチを切り替えた状態では削除しない。
統合済みの判定には記録した親ブランチを使う。

## PR / Issue / ブランチから開く

Herdr内で `gh-dash` を起動し、PR / Issue一覧から `w` で作業用worktreeを開く。
PR一覧の `r` は、修正用checkoutではなく下記の隔離PRレビューを起動する。
一覧・表示設定は既存設定を取り込んだ `~/.config/gh-dash/config.yml` で管理する。
gh-dash本体はmiseのAqua backendから導入し、`~/.local/bin/gh-dash` で起動する。

lazygitではローカル／リモートブランチ一覧の `B` から同じ処理で開く。`W` は既定のdiffのまま。
どちらもWorktrunkで作成・再利用する。Herdr内ではworkspaceへフォーカスする。
lazygitのブランチ作成はHerdr外でも使え、Worktrunkの結果を表示する。
Herdr workspaceの使用状況を確認できないHerdr外では削除を受け付けない。
設定済みのコピー・初期化を実行する。現在のcheckoutのブランチは変更しない。

CLIから直接指定する場合：

```sh
github-worktree pr 123 --repo owner/repo
github-worktree issue 456 --repo owner/repo
github-worktree pr 123 --repo owner/repo --review
github-worktree branch feat/example
github-worktree branch feat/example --remote origin
```

PRはそのPRのブランチを使う。Issueはdefaultブランチをfetchしたコミットから
`issue/<番号>` を作り、既存ブランチがあれば再利用する。
ローカルブランチ指定は既存ブランチのみ。存在しなければ作成せず停止する。
`--remote` 指定時はfetch済みのリモート追跡refから、選択remoteを追跡するローカルブランチを作る。
同名のローカルブランチが既にあれば、そのupstreamが選択refと一致する場合のみ再利用する。
未設定・別remoteを追跡している場合は停止し、強制更新や付け替えはしない。必要なら先にlazygitでfetchする。
PR / Issueのrepoは現在のcheckoutまたはHerdrで開いているcheckoutからremote一致で探す。
対象がなければ自動cloneせず停止するため、先にそのリポジトリをHerdrで開く。
旧Television一覧と `prw` / `issuew` は廃止した。

## 個人設定・初期化とコピー

共通設定は `~/.config/worktrunk/config.toml` の管理領域をchezmoiが更新する。
同ファイルの管理領域外に書いた個人設定は保持され、リポジトリには含まれない。
`wt config show` の `Identifier` を使い、リポジトリごとの設定を追加する。

```toml
[projects."github.com/example/project".pre-start]
dependencies = "npm ci"

[projects."github.com/example/project".pre-remove]
cleanup = "./scripts/cleanup-worktree"
```

ユーザー設定のコマンドはWorktrunkの承認対象外であり、設定者の責任で実行される。
共有設定 `.config/wt.toml` のコマンドは承認が必要。gh-dash、lazygitなどから対話端末で
操作すると、未承認のコマンドをその場で表示し、承認すれば操作を続行する。拒否または
承認状態を確認できない場合は停止する。承認は記録され、コマンドやプロジェクトの場所が
変わると再確認される。非対話環境では自動承認しない。手動で確認する場合は
`wt config approvals list`、承認する場合は `wt config approvals add` を使う。
`--yes` で承認を省略しない。

新規作成時、メインcheckoutの `.worktreeinclude` に一致する **Git ignore済みファイルだけ**を
初期化コマンドより先にコピーする。ファイルがなければ何もコピーしない。
既存ファイルは上書きしない。`.worktreeinclude` は共有・追跡してもよいし、
メインcheckoutだけに置き `.git/info/exclude` で個人用に隠してもよい。
`.env` を指定すると認証情報もレビュー・子worktreeへコピーされ得る。
無視されていない未追跡ファイルや追跡ファイルの未コミット変更はコピーしない。

```gitignore
# メインcheckoutの .worktreeinclude の例
.env.local
```

初期化は新規作成時のみ。既存worktreeを開き直しても再実行しない。
`pre-start` は完了を待つが、`post-start` はバックグラウンドで動く。
コピー後に必要な処理は `pre-start` に置き、順序が必要な複数処理はpipelineを使う。
共通の `pre-switch` / `pre-start` / `pre-remove` は管理領域で使用するため、個人の処理は
`[projects."<Identifier>".pre-start]` などのリポジトリ別設定に置く。

Herdr `prefix+t` とモバイルメニュー、lazygit、gh-dash、直接の `wt` はこの設定を使う。
Herdr標準のサイドバー作成と `herdr worktree create` はHerdr独自実装のため対象外。

## PRレビュー

レビュー本体と環境操作は分ける。明示 `--environment` を優先し、未指定なら現在のhostを
判定する。host不明・複数一致・必須能力不足では停止し、別環境へ自動fallbackしない。
`herdr` adapterは旧Herdr専用であり、herdr-core adapterはない。hc上から旧Herdrとして
代用したり `--environment herdr-core` を指定したりしない。手動のcore利用は
`pr-review` のprepared runではない。

```sh
pr-review --environment herdr --no-focus 123
pr-review --environment herdr --repo-path /path/to/repo --quick https://github.com/owner/repo/pull/123
pr-review --environment orca --project my-project 123
```

旧Herdrを選ぶ場合は旧Herdr管理下で実行する。番号はcwdまたは明示repo pathに属するPR。
Orcaの `--project` は登録名または `id:<repoId>` で、URLによる登録repo検索もOrca側が担当する。
Paseoは既知だが未対応の環境。現行CLIの能力を確認するまでは `unsupported-environment` として
run directory・checkout・session作成前に停止する。旧transportは復活させない。

URLとローカルrepositoryの一致、固定base/head、linked worktreeのGit common dir、
clean base checkoutを検証する。PR headの指示ファイルを起動時に読み込ませない。
私有sessionディレクトリと `autoResume: false` で履歴を分離する。
準備済み環境では追加worktreeやOMPを作らない。エージェントからの起動は `--no-focus` を付ける。

Herdr経路ではWorktrunkの設定済みコピー・hookを実行してcheckoutを作り、Herdr workspaceを開く。
checkout ownerは `worktrunk`、実行環境は `herdr` と記録する。設定によりローカルのignored fileや
承認済みproject commandがレビュー環境に入る。Orca経路は従来どおりOrca所有でsetupなし。
レビューはcheckoutのclean検証を維持するため、hookが追跡ファイルを変更したり
ignoreされていないファイルを生成した場合は、起動を止めてworktreeを保持する。
Herdrのprompt応答は受理の証拠までとし、実行開始や完了とは扱わない。

version 3 contextは実行環境、checkout owner、対話環境のIDを別に記録する。
成果物にはrun内へ保存したruntime・adapter・参照文書を使い、再開時に配布元の別版へ切り替えない。
旧version 2 runは保持するが、新runtimeでは受け付けない。必要な継続には旧runのsnapshotを使う。
返されたowner・path・workspace/paneまたはterminalのIDと送信証拠を記録する。
`accepted` は入力受理だけを示す。開始未確認なら同じ資源を確認し、自動で再送しない。

実際の branch/SHA は base checkout の値として開始時に開示し、対象の固定 head SHA と
混同しない。head のソースは trusted runtime の `read-source` で固定 blob として読む。
`base` 指定は PR 差分の merge-base を指すため、実行中の base SHA と異なる場合がある。
比較では replacement refs を無効にし、shallow repository や複数 merge-base は拒否する。
head の指示を読み込むための checkout、追加の可視環境、未承認の PR コード実行は行わない。

全 changed file の `coverage.json` と範囲付き read ledger を残し、未読・省略・理由付き
除外を報告する。追加／削除の不存在側や file と directory を区別し、rename は旧・新 path
で比較する。純粋な rename や diff context 行には inline finding の変更行を割り当てない。
静的確認・公式仕様・既存 CI・ローカル実行を区別する。CI／local の実行根拠には固定 head の
`targetSha` を持つ `pass` または `fail` check を使い、`not_run` は使わない。`executed` は
成功を意味せず、この契約も PR script の実行を要求しない。同じ session の逐次確認を
独立レビューとは呼ばず、委譲と完了 lens の実際の route を整合させる。

JSON 成果物を構成したら `render-summary <prepared-context.json>` の JSON `markdown` を
取得し、start/end marker 付き canonical summary block を報告へ一度だけ挿入する。
block は件数・除外・未読、checkout/target、plan/profile、委譲・lens route、check 結果と
制限を canonical 成果物から生成する。render は承認や検証完了ではない。成果物変更後は
再生成し、最終報告前と投稿前に `validate-review` で唯一の block の完全一致、
Verdict/Coverage/finding heading と metadata・証跡の整合を検査する。

結果と環境は確認・追加質問用に残す。投稿や終了だけを理由に自動削除しない。
GitHubへの投稿は明示確認後に行う。起動失敗、timeout、blocked、unknownは完了ではなく、
環境を保持して原因を確認する。

## 所有権と終了

作成時にcheckout owner（旧Herdr／Orca／Worktrunk／external）、絶対path、branch、base SHAを記録し、
実行環境のsession/workspace、core terminal address、app pane IDとagent identityは別に記録する。
terminalを表示・非表示にしてもcheckout ownerは変わらない。terminalやpaneがあること、
Worktrunk一覧に載ることだけで、checkoutのownerを推定しない。

- 旧Herdrで作ったworktreeは旧Herdr経路で終了する。
- Orcaで作ったレビュー環境は、明示的な終了承認後にOrca経路で終了する。成果物は残す。
- Worktrunkで作ったworktreeはWorktrunk経路で終了する。hcや表示pane内で使っていてもownerは変わらない。
- 既存・外部所有のworktreeは削除しない。
- 実行中、未保存、未統合、保留、所有権不明の場合は保持する。
- force／clobberを標準にしない。ブランチ削除は別判断にする。

共通設定では `wt remove` はブランチを残し、未コミット変更を強制削除しない。
自動化でも `--no-delete-branch --foreground --format json` で結果を確認する。
Gitがignoreするファイルは通常のdirty判定に含まれず、worktree削除で一緒に消える場合がある。
`.env` や生成物に未保存の変更がないか、削除前に確認する。MADの削除はignored fileも検査し、
残っていれば停止する。

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
