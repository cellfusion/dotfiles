## 手動オーケストレーション

MAD は親エージェントが実行の進行を管理する。レシピを開始するたびに、次の共通契約を使う。

1. 親は一意な run ID を発行し、作業ディレクトリ配下に
   `_cellfusion/orchestration/<run-id>/` を作る。親は run 全体の状態と各子の成果物をこの
   ディレクトリに集める。
2. 親は最初に Paseo MCP の接続可否を確認する。利用可能なら Paseo MCP で子を起動し、状態確認、
   ログ取得、中断を行う。`manual-orchestration-validate --select-backend` は backend selector の
   成果物形式を確認できる。利用できない場合だけ、`[dispatch-subagent: role]` で組み込みの
   subagent を起動する。実行開始後の失敗を別 backend へ自動的に切り替えてはならない。
3. run 全体の状態は `<run-dir>/state.json` だけに保存する。子の成果物は必ず
   `<run-dir>/nodes/<node-id>/attempts/<attempt-id>/` に分離し、その中に `prompt.md`、
   `result.md` または `result.json`、`state.json`、`handoff.json`、`log.md` を残す。`handoff.json`
   には後段へ渡す `artifact_paths` を絶対パスだけで記録する。node 直下に成果物や
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

- run state: `run_id`、`recipe`、`state`、`phase`、`phase_state`、`next_action`、`current_round`、
  `started_at`、`finished_at`、`backend`、`backend_reason`、`parent_decision`、`active_nodes`、
  `completed_nodes`、`adopted_attempts`、`artifact_paths`。ユーザー判断が必要なときは
  `decision_request` に request ファイルの絶対パスを記録する。worktree を作る run では、確定した
  base を `base` に記録する。
- attempt state: `run_id`、`node`、`attempt`、`round`、`state`、`phase`、`phase_state`、`next_action`、
  `started_at`、`finished_at`、
  `backend`、`backend_reason`、`parent_decision`。`node`、`attempt`、`round` はディレクトリ名や
  ログの文言ではなく state の第一級フィールドである
- `state`: `pending`、`running`、`waiting_for_user`、`ok`、`failed`、`stopped`、`unresolved` の
  いずれか。user gate では run の `state` と `phase_state` を `waiting_for_user` にする。
- `started_at` と `finished_at`: 状態が変わった時刻。未開始・実行中なら未設定でもよい
- `backend`: `paseo-mcp` または `subagent` と、選択理由
- `error`: 失敗時のエラー概要。成功時は空でもよい
- `parent_decision`: 親が確認した境界での継続、再実行、停止、統合の判断

attempt state の `run_id`、`node`、`attempt` は、それぞれ run、node、attempt のディレクトリ名と
一致させる。`round` は run state の `current_round` 以下の非負整数にする。この照合によって、並列子の
書き込み先取り違えや再実行による成果物の上書きを検出する。

`adopted_attempts` は node ID から親が採用した attempt ID への map である。run を `ok` にする前に、
各完了 node の採用 attempt を明示する。採用 attempt が `ok` なら、履歴上の `failed` attempt は retry
成功を妨げない。親は採用 attempt の `handoff.json` だけを後段へ渡し、本文を会話へ転記しない。

### 子の起動

`mad-attempt-v1` は attempt の成果物契約の名前である。`~/.agents/agent-defs/manifests.json` の
`artifact_contract` がこの値を持つ role は、次の 3 つを満たす。第 1 に、子は role の schema に従う
JSON だけを返し、本文を親へ返さない。第 2 に、親はその JSON を attempt の `result.json` に保存する。
第 3 に、親は JSON に含まれる絶対パスを attempt の `handoff.json` の `artifact_paths` へ写す。

親は子を起動する前に、attempt ディレクトリの `prompt.md` を書く。`prompt.md` は 3 つを含む。
role の指示は `~/.agents/agent-defs/prompts/<role>.md` の内容とし、入力は成果物の絶対パスだけとし、
出力形式は `~/.agents/agent-defs/schemas/<role>.json` の内容と「この schema に従う JSON だけを返す」
という指示とする。どちらのファイルも `chezmoi apply` 前は存在しないので、その場合はこの
checkout の `.chezmoitemplates/agent-defs/` 側を読む。

- Paseo MCP: `create_agent` の `provider` を `~/.agents/agent-defs/paseo-routing.json` の第 1 候補から
  決め、`initialPrompt` に `prompt.md` の内容をそのまま渡す。`create_agent` は system prompt も
  出力 schema も別の引数に取らないため、両方を `initialPrompt` に含める。
- native subagent: `[dispatch-subagent: <role>]` で起動する。role の定義は
  `~/.agents/agent-defs/prompts/<role>.md` から生成済みなので、渡すのは入力と出力形式だけでよい。

親は子の構造化出力を attempt の `result.json` へ保存する。schema に合わない出力は親が整形せず、
その attempt を `failed` として記録する。schema を持たない補助的な子だけが `result.md` を残す。

### worktree 隔離

`implement` と `spike` は子が同時にファイルを書くので、node ごとに worktree を作る。同じ
作業ディレクトリで並列に起動すると、子の書き込みが互いを上書きする。

- Paseo MCP: `mcp__paseo__create_workspace` を呼ぶ。`isolation` は `worktree`、`mode` は
  `branch-off`、`path` は呼び出し元のパス、`branchName` は `mad/<run-id>/<node-id>`、
  `baseBranch` は確定した base、`title` は node の用途を示す文字列にする。返る `workspaceId` を
  `mcp__paseo__create_agent` の `workspaceId` に渡す。`workspaceId` を渡すときは、作業ディレクトリを
  別に指定しない。
- native subagent: `Agent` ツールの `isolation` に `worktree` を渡す。

作った workspace は run ディレクトリ直下の `workspaces.json` に記録する。形式は node ID をキーとし、
値が `workspace_id`、`cwd`、`branch`、`archived` を持つ object である。`cwd` は絶対パスにする。
`archived` は作った時点では `false` にする。

`_cellfusion/` は git 管理外なので worktree の中には現れない。子へ渡す要件ファイルは絶対パスにする。

### base の確定

`base` 引数が空なら、親は現在のブランチを base として使う。detached HEAD なら base を決められない
ので、run を開始せずに止める。

確定した base は run の `state.json` の `base` に記録する。run state が base の唯一の記録である。

### 成果物契約の受け入れ検証

親は子を起動する backend と切り離して、run の完了前に次を実行する。これは Paseo MCP の実在ツールを
呼ばず、作成済みの state と成果物だけを検証する。`chezmoi apply` 前は配布先に validator が無いので、
その場合はこの checkout のソース側を使う。

```bash
MAD_VALIDATE="$HOME/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate"
if [ ! -x "$MAD_VALIDATE" ]; then
  MAD_VALIDATE="$(git rev-parse --show-toplevel)/private_dot_agents/skills/multi-agent-development/scripts/executable_manual-orchestration-validate"
fi
bash "$MAD_VALIDATE" "$RUN_DIR"
```

validator が失敗した run は `ok` にせず、親が `failed` または `stopped` と記録して確認する。

レシピごとに、run を `ok` にする前に `completed_nodes` と `adopted_attempts` へ入っていなければ
ならない node がある。親はこの node ID をそのまま使う。

| レシピ | 必須 output node |
|---|---|
| `research` / `fanout` | `synthesis` |
| `decide` / `debate` | `verdict` |
| `spec` | `spec-author` |
| `plan` | `planner` |
| `implement` / `delivery` | `final-review` |
| `review` | `review-synthesis` |

run の `state` が `pending` または `running` の間は、`phase_state` に完了した phase の状態を
残してよい。それ以外の `state` では `phase_state` を `state` と同じ値にする。

### 親の介入境界とループ

並列子の完了後、統合や裁定の起動前に、親が確認する境界を置く。親は成果物を確認して追加指示を
出し、一部の子だけを再実行し、後段の指示や出力形式を変更し、または run を停止できる。

ループを持つレシピでは、各ラウンドの開始・完了、子の成果物、`parent_decision` を run の
`state.json` に記録する。`max_rounds` は必須の安全上限であり、上限に達したら成功扱いにせず、
最終状態を `unresolved` として保存して停止する。

### 後片付け

run を終えたら、`workspaces.json` の各 workspace を `mcp__paseo__archive_workspace` で片付け、その
node の `archived` を `true` にする。

archive に失敗した workspace がある run は、run ディレクトリを消さない。台帳を失うと、どの run が
どの workspace を作ったかの対応が追えなくなる。

`archived` が `false` の workspace が 1 つでも残っている run を `ok` にしない。
