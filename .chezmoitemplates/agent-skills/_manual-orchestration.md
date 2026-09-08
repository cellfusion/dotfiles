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
  `started_at`、`finished_at`、`child_ref`、
  `backend`、`backend_reason`、`parent_decision`。`node`、`attempt`、`round` はディレクトリ名や
  ログの文言ではなく state の第一級フィールドである
- `state`: `pending`、`running`、`waiting_for_user`、`ok`、`failed`、`stopped`、`unresolved` の
  いずれか。user gate では run の `state` と `phase_state` を `waiting_for_user` にする。
- `started_at` と `finished_at`: 状態が変わった時刻。書式は UTC の ISO 8601、すなわち
  `YYYY-MM-DDTHH:MM:SSZ` とする。`state` が `running` の attempt では `started_at` を必須にする。
  期限超過の判定が `started_at` を読むためである。`finished_at` は未完了なら未設定でもよい
- `child_ref`: 親が起動した子の識別子。Paseo MCP なら `mcp__paseo__create_agent` が返した
  `agentId`、`Agent` ツールなら `Agent` ツールが返した識別子を入れる。この値が無いと、親は後から
  子の生存を確認できない。`state` が `pending` の attempt は子をまだ起動していないので
  `child_ref` を持たなくてよい。それ以外の `state` では非空の文字列にする
- `backend`: `paseo-mcp` または `subagent` と、選択理由
- `error`: 失敗時のエラー概要。成功時は空でもよい
- `parent_decision`: 親が確認した境界での継続、再実行、停止、統合の判断

親は子を起動した直後に、その attempt state の `child_ref` と `started_at` を書く。書いてから
「子の完了検知」の見張りを起動する。

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
provider id を別の provider id へ読み替える対応表である。

`roles` の置き換えと `providerMap` の間で、親は自分が動いている AI 環境を候補に当てる。当てるのは
validator の `--resolve-candidates` である。`MAD_VALIDATE` の決め方は「成果物契約の受け入れ検証」と
同じである。このブランチを merge した後に `chezmoi apply` を実行してから MAD を使うため、配布先の
validator を使う。

```bash
MAD_VALIDATE="$HOME/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate"
bash "$MAD_VALIDATE" --resolve-candidates researcher
bash "$MAD_VALIDATE" --resolve-candidates researcher '[{"provider":"claude"}]'
```

第 2 引数を渡さないときは `paseo-routing.json` の候補を使う。rule の `roles` で候補を差し替えた
親は、差し替えた後の配列を第 2 引数に渡す。

`--resolve-candidates` は、環境変数 `AGENT_ENV` が持つ環境名を候補の provider id に付ける。Paseo は
provider ごとに `AGENT_ENV` を注入するので、親が `claude-work` で動いていれば `work` が入る。
`AGENT_ENV` が `default` か未設定なら、先頭環境は接尾辞を持たないので候補を変えない。それ以外の
環境では、`codex` と `claude` の候補が `codex-work`、`claude-work`、`codex`、`claude` の順に
なる。同じ環境の provider を先に置き、読み替え前の候補を後ろに残す。同じ環境の provider が
すべて使えないときだけ、親は後ろの候補へ落とす。

`--resolve-candidates` の出力に rule の `providerMap` を当てる。仕事のリポジトリで使う provider を
`providerMap` が名指ししている場合、その指定が環境の読み替えより優先する。親はこの読み替え後の
provider id で利用可能性と model を確認する。

親は候補を確定する前に、候補の provider id をすべて validator へ渡して 5 時間のセッション枠の残量を
確かめる。`MAD_VALIDATE` の決め方は「成果物契約の受け入れ検証」と同じで、`chezmoi apply` 前は配布先に
validator が無いのでソース側を使う。

```bash
bash "$MAD_VALIDATE" --check-usage claude-work claude codex-work codex
```

出力は 1 行 1 provider の JSON object で、引数の順に並ぶ。フィールドは `provider`、`session_pct`、
`session_resets_at`、`verdict` の 4 つである。`session_pct` は 5 時間のセッション枠の使用率で、整数か
`null` になる。`session_resets_at` はセッション枠の回復時刻で、unix 時刻の整数か `null` になる。
`verdict` は `ok`、`low`、`exhausted`、`unknown` のいずれかで、使用率が 95 以上なら `exhausted`、
80 以上なら `low`、それ未満なら `ok`、使用率が取れないなら `unknown` になる。

親は候補を次の順で並べ直す。

1. `--resolve-candidates ROLE [CANDIDATES_JSON]` で AI 環境を当てた候補の並びを得る。
2. 一致した rule の `providerMap` を当てる。
3. 並べ直した後の provider id をすべて `--check-usage` に渡す。
4. `verdict` が `exhausted` の候補を、互いの相対順序を保ったまま末尾へ移す。`low` と `unknown` は
   移さない。
5. 移した候補と理由を attempt state の `backend_reason` に書く。
6. 並べ直した候補に対して、この節の残りの手順どおり可用性と model と `thinkingOptions` を確かめる。

すべての候補が `exhausted` だったときは、親は子を起動しない。run の `state` と `phase_state` を
`waiting_for_user` にし、`next_action` に全候補が `exhausted` であることと最も早い
`session_resets_at` を書いてユーザーへ渡す。`session_resets_at` は unix 時刻なので、ユーザーへ渡す
前に読める時刻へ変換する。残量のある候補が無い状態で起動すると、成果物を残さずに終わる子を作り、
再実行も同じ結果になるためである。子を起動しなかった attempt は `state` を `pending` のまま残す。

残量が分からないときは run を止めない。`--check-usage` は `unknown` を返して終了コード 0 で終わる。
親は `unknown` の候補を並べ直しの対象にしない。

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

native subagent 側は `~/.agents/agent-defs/routing.json` の engine 解決に従う。native subagent は
provider を選ばず、親のプロセスから環境変数を継承する。どの環境のアカウントで動くかは、親を
起動した Paseo の provider が注入した `CLAUDE_CONFIG_DIR` と `CODEX_HOME` が決める。親はこの
2 つを子へ渡す前に書き換えない。

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

### 子の完了検知

親は子を起動した直後に、その attempt に対する見張りを 1 つ、背景の Bash で起動する。前面の Bash では
`sleep` が拒否されるため、`run_in_background` を `true` にして起動する。背景の Bash は終了時に親を
呼び戻すので、通知が届かない子でも親が必ず再開する。

Paseo MCP の子は `paseo wait` で待つ。

```bash
CHILD_REF="<create_agent が返した agentId>"
status="$(paseo wait "$CHILD_REF" --timeout <待ち時間> --json 2>/dev/null | jq -r '.status // "unknown"')"
printf 'watchdog %s %s\n' "$CHILD_REF" "$status"
```

`paseo wait` は子が `idle` になるまで待ち、`--timeout` の秒数を超えたら戻る。返す JSON の `status` は
`idle`、`timeout`、`error` のいずれかである。終了コードはどの場合も 0 なので、親は終了コードではなく
`status` で判断する。`--json` の `message` は子の直近の活動履歴を全文で持つため、親は
`jq -r '.status'` で 1 語だけを取り出す。JSON をそのまま出力すると、別の子の本文が親の文脈へ流れ込み、
「本文を親の会話へ転記しない」という契約に反する。

`Agent` ツールの子は shell から生存を確認する手段が無いので、待ち時間だけで終わる。

```bash
CHILD_REF="<Agent ツールが返した識別子>"
sleep <待ち時間>
printf 'watchdog %s timeout\n' "$CHILD_REF"
```

`<待ち時間>` は「既定値」の表が持つ秒数を使う。既定は 1200 秒、`implement` と `spike` は 3600 秒で
ある。親がレシピごとに値を指定した場合は、指定した値を使う。

見張りが終わると親に通知が届く。親は次の順で処理する。

1. 子の完了通知を先に受け取っていたなら、見張りを `TaskStop` で止め、通常どおり成果物を確認する。
   停止に失敗しても構わない。後から届く `watchdog ... timeout` は、attempt に構造化出力が既にある
   ため 2 の判定で通常の処理へ進む。
2. 完了通知を受け取っていないなら、attempt に構造化出力が残っているかを確認する。残っていれば
   通常どおり処理する。
3. 出力が無く、見張りの `status` が `idle` だったなら、その子は成果物を残さずに終了している。親は
   attempt を `failed` として記録し、`error` に構造化出力が無いことと `status` の値を書く。同じ node に
   新しい `<attempt-id>` を発行して、同じ backend で 1 回だけ再実行してよい。再実行の前に「provider と
   model の解決」の残量確認を通す。
4. 出力が無く、`status` が `timeout`、`error`、`unknown` のいずれかだったなら、親は再実行しない。
   run の `state` と `phase_state` を `waiting_for_user` にし、`next_action` に裁定待ちであることと
   `status` の値を書いてユーザーへ渡す。子が生きたまま二重に走ることを防ぐためである。`Agent`
   ツールの子は常にこの経路へ入る。

親は `mcp__paseo__create_agent` の `notifyOnFinish` を既定の `true` から変えない。見張りは通知の
代わりではなく、通知が届かない場合の受け皿である。

1 attempt につき見張りは 1 つとする。見張りは子を停止せず、観測した `status` を親へ返すだけである。

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
呼ばず、作成済みの state と成果物だけを検証する。このブランチを merge した後に `chezmoi apply` を
実行してから MAD を使うため、配布先の validator を使う。

```bash
MAD_VALIDATE="$HOME/.agents/skills/multi-agent-development/scripts/manual-orchestration-validate"
bash "$MAD_VALIDATE" "$RUN_DIR"
```

validator が失敗した run は `ok` にせず、親が `failed` または `stopped` と記録して確認する。

validator は `overdue attempt: <node>/<attempt> started_at=<値> elapsed=<秒>s limit=<秒>s` の行を
標準出力へ出すことがある。`state` が `running` の attempt が、`started_at` から待ち時間を超えて
残っているという観測結果であり、契約違反ではないので終了コードは 0 のままである。この行を受け取った
親は「子の完了検知」の 3 と 4 の手順へ進む。待ち時間は recipe から決まり、run state に
`child_timeout_seconds` が正の整数としてあればその値を使う。この行は run の `state` によらず出るので、
`stopped` の run に残った `running` の attempt も報告の対象になる。

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

子は、判断に必要な情報が欠けるときに推測で成果物を完成させてはならない。要求の伝え方は role の
`access` で 2 通りに分かれる。`access` は `~/.agents/agent-defs/manifests.json` が role ごとに持つ。

要求に書くものは、どちらの経路でも次の 4 つである。

- 質問 — 何を決めてほしいかを 1 文で書く
- 選択肢 — 選べる案を 2 つ以上挙げ、それぞれ選ぶと何をするのかを書く
- 推す案とその理由 — どれかを推すなら、推す案と理由を書く。推さないなら、推せない理由を書く
- 確認済みのこと — 判断できないと分かった時点で、何を調べて何が分かったかを書く

**`access` が `write` の role**（`spec-author`、`plan-author`、`implementer`、`writer`）は、attempt
ディレクトリの `decision-request.md` に要求を書き、構造化出力の `decisionRequestPath` にその絶対
パスを入れて返す。判断を求めないときは `decisionRequestPath` を `null` にする。親は子を起動する前に、
その attempt の `decision-request.md` の絶対パスを決め、`prompt.md` の入力に
`DECISION_REQUEST_PATH` という名前で含める。role の指示はこの名前で書き先を参照する。

**`access` が `read` の role**（`reviewer`、`researcher`、`judge`、`synthesizer`、
`review-synthesizer`）は、ファイルを書く手段を持たない。この role には書き込み系のツールを渡さない
ためである。要求は構造化出力の `decisionRequest` に入れて返す。`decisionRequest` は上の 4 つを
`question`、`options`、`recommendation`、`confirmed` として持つ object である。判断を求めないときは
`decisionRequest` を `null` にする。親はこの role に `DECISION_REQUEST_PATH` を渡さない。

親は子の完了後に `result.json` を読む。`decisionRequestPath` が `null` でない場合、または
`decisionRequest` が `null` でない場合、判断が要る。

`decisionRequest` を受け取った場合、親がその内容を attempt ディレクトリの `decision-request.md` へ
書く。書き方は上の 4 つを見出しにした Markdown とし、`options` は箇条書きにする。子の代わりに
書くのは親であるが、中身を作り直してはならない。

どちらの経路でも、親は run の `state` と `phase_state` を `waiting_for_user` にし、run state の
`decision_request` に `decision-request.md` の絶対パスを記録する。親は `decision-request.md` を
読んで [ask-user] でユーザーへ渡す。親が子に代わって判断してはならない。

ユーザーの回答を受け取ったら、親は同じ node に新しい `<attempt-id>` を発行し、その attempt
ディレクトリに `decision.md` を書く。`decision.md` には、ユーザーが選んだ案と、ユーザーが添えた
指示をそのまま書く。親は `decision.md` の絶対パスを入力に加えて同じ role を起動する。既存 attempt
のファイルを上書きしてはならない。

子を起動するときに、親は run state の `decision_request` を `null` に戻し、`state` と `phase_state` を
`running` に戻す。古い attempt の request ファイルを指したままにすると、`decision_request` が
run の現在の状態を表さなくなる。

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
