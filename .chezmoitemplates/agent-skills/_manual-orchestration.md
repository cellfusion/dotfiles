## 手動オーケストレーション

MAD は親エージェントが実行の進行を管理する。レシピを開始するたびに、次の共通契約を使う。

1. 親は一意な run ID を発行し、作業ディレクトリ配下に
   `_cellfusion/orchestration/<run-id>/` を作る。親は run 全体の状態と各子の成果物をこの
   ディレクトリに集める。
2. 親は最初に Paseo MCP の接続可否を確認する。利用可能なら Paseo MCP で子を起動し、状態確認、
   ログ取得、中断を行う。利用できない場合だけ、`[dispatch-subagent: role]` で組み込みの
   subagent を起動する。実行開始後の失敗を別 backend へ自動的に切り替えてはならない。
3. run 全体の状態は `<run-dir>/state.json` だけに保存する。子の成果物は必ず
   `<run-dir>/nodes/<node-id>/attempts/<attempt-id>/` に分離し、その中に `prompt.md`、
   `result.md` または `result.json`、`state.json`、`log.md` を残す。node 直下に成果物や
   `state.json` を置いてはならない。同じ node を再実行するときも新しい `<attempt-id>` を発行し、
   既存 attempt のファイルを上書きしてはならない。
4. 親は子の完了後に `state.json` と成果物を確認する。親が確認して次の処理を許可するまで、
   統合・裁定・次のラウンドへ自動的に進めてはならない。失敗した子は親が再指示、再実行、停止を
   判断し、失敗を隠して統合してはならない。
5. 統合役や後段の子には、本文を会話へ転記せず、入力成果物の絶対パスだけを渡す。親が読むのは
   状態と必要最小限の統合要約とし、子の本文を親の最終応答へ自動転記しない。

### run とノードの状態

run の `state.json` と attempt の `state.json` は別の責務を持つ。双方とも JSON object とし、
パスの名前だけに依存せず、識別子を state の第一級フィールドとして保存する。

- run state: `run_id`、`recipe`、`state`、`current_round`、`started_at`、`finished_at`、`backend`、
  `backend_reason`、`parent_decision`
- attempt state: `run_id`、`node`、`attempt`、`round`、`state`、`started_at`、`finished_at`、
  `backend`、`backend_reason`、`parent_decision`。`node`、`attempt`、`round` はディレクトリ名や
  ログの文言ではなく state の第一級フィールドである
- `state`: `pending`、`running`、`ok`、`failed`、`stopped`、`unresolved` のいずれか
- `started_at` と `finished_at`: 状態が変わった時刻。未開始・実行中なら未設定でもよい
- `backend`: `paseo-mcp` または `subagent` と、選択理由
- `error`: 失敗時のエラー概要。成功時は空でもよい
- `parent_decision`: 親が確認した境界での継続、再実行、停止、統合の判断

attempt state の `run_id`、`node`、`attempt` は、それぞれ run、node、attempt のディレクトリ名と
一致させる。`round` は run state の `current_round` 以下の非負整数にする。この照合によって、並列子の
書き込み先取り違えや再実行による成果物の上書きを検出する。

### 成果物契約の受け入れ検証

親は子を起動する backend と切り離して、run の完了前に次を実行する。これは Paseo MCP の実在ツールを
呼ばず、作成済みの state と成果物だけを検証する。

```bash
~/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate "$RUN_DIR"
```

validator が失敗した run は `ok` にせず、親が `failed` または `stopped` と記録して確認する。

### 親の介入境界とループ

並列子の完了後、統合や裁定の起動前に、親が確認する境界を置く。親は成果物を確認して追加指示を
出し、一部の子だけを再実行し、後段の指示や出力形式を変更し、または run を停止できる。

ループを持つレシピでは、各ラウンドの開始・完了、子の成果物、`parent_decision` を run の
`state.json` に記録する。`max_rounds` は必須の安全上限であり、上限に達したら成功扱いにせず、
最終状態を `unresolved` として保存して停止する。
