# hc テンプレートの使い方

`hc` のテンプレートは、起動する対話型エージェントと初回の役割指示をまとめたものです。
依頼文は `hc run` で別に渡します。固定の自動実行パイプラインではなく、作業ごとに役割を選びます。
`command: omp` を使い、モデルや権限は実行環境の既定値に従います。

| 名前 | 用途 |
|---|---|
| `implement` | 指定範囲の実装と利用経路の確認 |
| `debug` | 症状の切り分け。修正を依頼した場合は修正と再現確認まで |
| `review` | 差分・PRの読み取り専用レビュー。投稿や承認はしない |
| `research` | コード・仕様・運用の調査。調査のみなら対象を変更しない |
| `ui` | UIの改善と実画面・操作の確認 |

## 配置と起動

chezmoi sourceの `private_dot_config/herdr-core/templates/` に保存します。対象の適用を明示的に
承認した後、次のコマンドでテンプレートとこのガイドを配置できます。

```sh
chezmoi apply ~/.config/herdr-core/templates ~/.config/docs/herdr-core-templates.md
hc templates
```

適用前は `hc templates` に現れません。各ファイルの名前がテンプレート名になります。
実行するマシン側にテンプレートと `omp` が必要です。`--on` の場合もリモート側で解決されます。

```sh
hc run --json --bg --name fix-login --cwd /path/to/repo debug \
  'ログイン後の画面遷移不具合を調査し、原因を修正して再現確認してください。'
hc wait fix-login
hc read --lines 100 fix-login
```

`--cwd` は対象checkoutの絶対パスに、`--name` は他の稼働中terminalと重ならない名前に変えてください。
`--json` の `first_message.sent` が `false` なら初回指示は送られていません。画面と準備状態を確認し、
信頼確認などが必要なら解決してから送信してください。送信失敗時も二重送信の前に画面を確認します。
`hc wait` の結果だけで依頼の完了を決めず、`hc read` で内容を確認します。

## 親エージェントから委譲するとき

同じrepositoryの通常の委譲はOMP内の機能を優先し、独立した担当が必要なときに `hc` を使います。
依頼には対象repository・checkout、担当範囲、非対象、完了条件、確認の担当者、依頼IDと
**確認済みの親terminalアドレス**を含めます。返答先の `$HC_TERMINAL_ID` は親側で展開して渡します。
子側で展開すると子自身のアドレスになるため、そのまま返答先に使えません。

テンプレートは返答先を推測せず、指定された場合だけ `hc send` で報告します。
指定がなければそのセッション内に結果を残すので、`hc read` または `hc attach` で確認してください。
複数担当の編集範囲が重なる場合は統合担当を決め、他の変更を上書きしないようにします。
自動commit・push・デプロイ・設定適用はせず、その都度の依頼に従います。

通信・待機・blocked時の扱いやterminalの後片付けは、導入済みバージョンの `hc --skill` と
`herdr-core` スキルを参照してください。worktreeの所有権はterminalとは別に扱います。
