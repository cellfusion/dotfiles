## 手動オーケストレーション

MAD は親エージェントが実行の進行を管理する。レシピを開始するたびに、次の共通契約を使う。

1. 親は一意な run ID を発行し、`~/.agents/skills/_shared/scripts/cellfusion-workdir` を
   実行してから、作業ディレクトリ配下に `_cellfusion/orchestration/<run-id>/` を作る。
   `cellfusion-workdir` は `_cellfusion/.gitignore` を書くので、`~/.config/git/ignore` に
   `_cellfusion` が無い環境でも run の成果物が呼び出し元のリポジトリに混ざらない。親は run
   全体の状態と各子の成果物をこのディレクトリに集める。
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

### provider と model の解決

親は子を起動する前に `mcp__paseo__list_providers` と `mcp__paseo__list_models` で可用性を
確かめる。そのうえで `mcp__paseo__create_agent` の `provider`、`settings.thinkingOptionId`、
`settings.modeId` を決める。

`mcp__paseo__list_providers` は全 provider を絞り込まずに返す。各 provider は `enabled`（真偽値）と
`status`（`available` または `unavailable`）を持つ。親は `enabled` が `true` かつ `status` が
`available` の provider だけを利用可能として扱う。どちらか一方でも条件を満たさない provider は
候補から外す。

候補の優先順位は `~/.agents/agent-defs/paseo-routing.json` が role ごとに持つ。リポジトリごとの
上書きは `~/.agents/agent-defs/paseo-project-routing.json` が持つ。rule は git remote かリポジトリの
パスで照合する。ssh 形式 (`git@host:path`) と https 形式の remote は、どちらも `host/path` に
正規化してから比べる。

一致した rule は、候補に 2 段階の上書きを掛ける。第 1 に、rule の `roles` に対象の role の項が
あるとき、その配列が `paseo-routing.json` の候補配列そのものを置き換える。`roles` に対象の role が
無いときは `paseo-routing.json` の候補をそのまま使う。第 2 に、rule の `providerMap` は候補の
provider id を別の provider id へ読み替える対応表である。置き換えた後の候補に `providerMap` を
当てる。親はこの読み替え後の provider id で利用可能性と model を確認する。

tier と access から model・thinking・mode への対応は `~/.agents/agent-defs/paseo-providers.json` が
持つ。tier と access は `~/.agents/agent-defs/manifests.json` の role の項が持つ。親は候補を
優先順位どおりに調べ、次のすべてを満たす最初の候補を採用する。第 1 に、provider が利用可能である。
第 2 に、`mcp__paseo__list_models` にその provider の対応 model が載っている。第 3 に、その model の
`thinkingOptions` が、tier に対応する thinking option を含む。model が存在しても要求する
`thinkingOptions` を持たない場合は、その候補を採用しない。

どの候補も使えない場合は推測で代替せず止める。

`paseo-providers.json` の `modes` は role の `access` を provider の mode に対応させる表である。
claude の `write` が対応する `bypassPermissions` は、許可の確認を出さないモードであり、書き込める
パスの制限ではない。書き込む役が worktree の外に書かない保証は、role のプロンプトの指示だけである。
仕事のリポジトリでこの mode を使うかどうかは利用者が判断する。

native subagent 側は `~/.agents/agent-defs/routing.json` の engine 解決に従う。

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

- Paseo MCP: `create_agent` の `provider`、`settings.thinkingOptionId`、`settings.modeId` は
  「provider と model の解決」の手順で決め、`initialPrompt` に `prompt.md` の内容をそのまま渡す。
  `create_agent` は system prompt も出力 schema も別の引数に取らないため、両方を `initialPrompt`
  に含める。
- native subagent: `[dispatch-subagent: <role>]` で起動する。role の定義は
  `~/.agents/agent-defs/prompts/<role>.md` から生成済みなので、渡すのは入力と出力形式だけでよい。

親は子の構造化出力を attempt の `result.json` へ保存する。schema に合わない出力は親が整形せず、
その attempt を `failed` として記録する。schema を持たない補助的な子だけが `result.md` を残す。

### worktree 隔離

`implement` と `spike` は子が同時にファイルを書くので、node ごとに worktree を作る。同じ
作業ディレクトリで並列に起動すると、子の書き込みが互いを上書きする。

worktree を作るのは親である。`mcp__paseo__create_agent` は作成時に `workspaceId` を要求するので、
子を起動する前に workspace が存在している必要がある。親は台帳の `cwd` から diff を取るので、子が
別の場所に worktree を作ると親が取る diff が空になる。子は親が渡した worktree の中で働き、自分では
worktree を作らない。

- Paseo MCP: `mcp__paseo__create_workspace` を呼ぶ。`isolation` は `worktree`、`mode` は
  `branch-off`、`path` は呼び出し元のパス、`branchName` は `mad/<run-id>/<node-id>`、
  `baseBranch` は確定した base、`title` は node の用途を示す文字列にする。
  返り値は `workspaceId` と `cwd` を持つ。`cwd` は作られた worktree の絶対パスである。
  `workspaceId` を `mcp__paseo__create_agent` の `workspaceId` に渡し、`cwd` を台帳へ記録する。
  `workspaceId` を渡すときは、作業ディレクトリを別に指定しない。
- native subagent: `Agent` ツールの `isolation` に `worktree` を渡す。`workspace_id` には `Agent`
  ツールが返す子の識別子を、`cwd` には `git worktree list` で確認した worktree の絶対パスを記録する。

作った workspace は run ディレクトリ直下の `workspaces.json` に記録する。形式は node ID をキーとし、
値が `workspace_id`、`cwd`、`branch`、`integration`、`archived` を持つ object である。`cwd` は
絶対パスにする。`integration` は作った時点では `pending` にし、`archived` は作った時点では `false`
にする。

1 node につき workspace は 1 つとする。node が失敗して作り直す場合は、同じ workspace を再利用するか、
新しい node ID を発行する。台帳の既存の key を別の `workspace_id` で上書きしてはならない。上書きすると
前の `workspace_id` が台帳から消え、後片付けの対象から外れる。

`_cellfusion/` は git 管理外なので worktree の中には現れない。子へ渡す要件ファイルは絶対パスにする。

### base の確定

`base` 引数が空なら、親は現在のブランチを base として使う。detached HEAD なら base を決められない
ので、run を開始せずに止める。

確定した base は run の `state.json` の `base` に記録する。run state が base の唯一の記録である。

### diff の受け渡し

レビュー役と judge は worktree の中を見られない。実装役は別の workspace で働くので、後段が
自分の作業ディレクトリを読んでも実装の変更は現れない。親が差分を取り出して attempt へ置く。

親は `workspaces.json` のその node の `cwd` を `git -C <cwd> diff <base>...HEAD` に渡し、出力を
実装役の attempt ディレクトリの `diff.patch` に書く。diff を取るのは後片付けより前である。
`archived` が `true` になった workspace の `cwd` は既に存在しないので、archive の後では diff を
取れない。

上限行数は `implement` が 2000 行、`spike` が 800 行である。超えた分は切り、切ったことと元の
行数をファイル末尾に注記する。

後段には `diff.patch` の絶対パスだけを渡す。diff の本文を親の会話へ転記しない。

diff の取得に失敗したら、中身の無いレビュー依頼を作らず run を止める。親は `git` コマンドが
0 以外で終わった場合と、正常に終わって出力が空だった場合を区別する。前者は取得の失敗なので
run を `failed` として停止する。後者は変更が無いという結果なので、親が次の処理を判断する。

### 改稿前の退避

`refine` の親は、改稿役を起動する前に対象ファイルを attempt ディレクトリの `before/` へ複製する。
複製先は `before/<対象ファイルの basename>` とし、改稿役には対象ファイルの元のパスだけを渡す。
改稿を採用しないと決めたとき、親はこの複製から元の内容に戻す。attempt ディレクトリが持てる
ディレクトリは `before/` だけであり、`before/` は複製したファイルだけを持つ。

退避されるのは対象ファイルだけである。改稿役が同じディレクトリの別のファイルを変更した場合は
戻せない。親は改稿役への指示に、対象ファイル以外を変更しないことを書く。

対象ファイルが呼び出し元のパスの外にある場合は、run を開始せずに止める。

### 既定値

| 項目 | 値 |
|---|---|
| 子の待ち時間の既定 | 1200 秒 |
| `implement` と `spike` の子の待ち時間 | 3600 秒 |
| 同時に走らせる子の上限 | 4 |

親がレシピごとに値を指定した場合は、指定した値が既定より優先する。

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

### 子からの判断要求

子は、判断に必要な情報が欠けるときに推測で成果物を完成させてはならない。子は attempt
ディレクトリの `decision-request.md` に要求を書き、構造化出力の `decisionRequestPath` に
その絶対パスを入れて返す。判断を求めないときは `decisionRequestPath` を `null` にする。

`decision-request.md` に書くものは次の 4 つである。

- 質問 — 何を決めてほしいかを 1 文で書く
- 選択肢 — 選べる案を 2 つ以上挙げ、それぞれ選ぶと何をするのかを書く
- 推す案とその理由 — どれかを推すなら、推す案と理由を書く。推さないなら、推せない理由を書く
- 確認済みのこと — 判断できないと分かった時点で、何を調べて何が分かったかを書く

親は子の完了後に `result.json` の `decisionRequestPath` を読む。値が `null` でなければ、run の
`state` と `phase_state` を `waiting_for_user` にし、run state の `decision_request` にその絶対
パスを記録する。親は `decision-request.md` を読んで [ask-user] でユーザーへ渡す。親が子に代わって
判断してはならない。

ユーザーの回答を受け取ったら、親は同じ node に新しい `<attempt-id>` を発行し、その attempt
ディレクトリに `decision.md` を書く。`decision.md` には、ユーザーが選んだ案と、ユーザーが添えた
指示をそのまま書く。親は `decision.md` の絶対パスを入力に加えて同じ role を起動する。既存 attempt
のファイルを上書きしてはならない。

ユーザーが何も選ばずに閉じた場合は、run を `stopped` として記録して止める。推測で先へ進めない。

### 親の介入境界とループ

並列子の完了後、統合や裁定の起動前に、親が確認する境界を置く。親は成果物を確認して追加指示を
出し、一部の子だけを再実行し、後段の指示や出力形式を変更し、または run を停止できる。

ループを持つレシピでは、各ラウンドの開始・完了、子の成果物、`parent_decision` を run の
`state.json` に記録する。`max_rounds` は必須の安全上限であり、上限に達したら成功扱いにせず、
最終状態を `unresolved` として保存して停止する。

### 取り込み

`mcp__paseo__archive_workspace` は workspace が持つものをまとめて片付け、worktree の
ディレクトリを消す。`diff.patch` は上限行数で切られるので、archive の後には上限を超えた実装が
残らない。親は run を `ok` にする前に取り込みの判断を済ませる。

`implement` と `spike` の run を `ok` にする前に、親は各 workspace の実装成果を呼び出し元へ
取り込むか、取り込まないかを決める。判断は `workspaces.json` の各エントリの `integration` に
記録する。値は `pending`（未判断）、`merged`（取り込んだ）、`declined`（取り込まないと決めた）の
3 つである。

取り込む場合は、呼び出し元のチェックアウトでそのエントリの `branch` を merge し、`integration` を
`merged` にする。merge が衝突したら run を止め、衝突した branch と node を run の `state.json` の
`error` に記録する。親は衝突を自分で解消しない。

取り込まないと決めた場合は `integration` を `declined` にし、その理由を同じエントリの
`integration_reason` に書く。

`mcp__paseo__archive_workspace` を呼べるのは、そのエントリの `integration` が `pending` で
なくなった後だけである。`archived` が `true` の workspace の `cwd` は既に存在しない可能性が
あるので、diff の取得と取り込みは archive より前に行う。

### 後片付け

取り込みの判断が済んだら、`workspaces.json` の各 workspace を `mcp__paseo__archive_workspace` で
片付け、その node の `archived` を `true` にする。

archive に失敗した workspace がある run は、run ディレクトリを消さない。台帳を失うと、どの run が
どの workspace を作ったかの対応が追えなくなる。

`integration` が `pending` の workspace、または `archived` が `false` の workspace が 1 つでも
残っている run を `ok` にしない。
