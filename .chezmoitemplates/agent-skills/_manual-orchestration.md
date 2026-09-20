# strict MAD run の共通契約

この節は、親が複数 child の strict MAD run を開始すると決めた後にだけ適用する。MAD を使うか、単一 child を使うか、親が直接作業するかを決めるための gate ではない。単純な task、単独の調査、MAD を使わない plan ではこの節を読んでも実行しない。

strict MAD の実行 backend は `paseo-mcp` だけである。親は Paseo MCP の discovery、model discovery、agent create、state の記録を担当し、子の本文を会話へ転記しない。すでに strict MAD run を開始した後で Paseo MCP が利用できない場合は run を開始せず `waiting_for_user` として停止する。開始前なら、親は MAD を選ばず直接作業する経路を選べる。開始後に別の backend へ切り替えたり、別の transport を試したり、同じ create を retry したりしてはならない。

## 実行pathの初期化

配布済みのMAD scriptは`~/.agents/skills/.../scripts`にあり、`PATH`には依存しない。次を同じshellで一度だけ設定してから、以下の手順で使う。`AGENT_CONFIG`は正本configの場所であり、共有module置き場ではない。

```bash
MAD_SCRIPTS="${MAD_SCRIPTS:-$HOME/.agents/skills/multi-agent-development/scripts}"
MAD_SHARE="${MAD_SHARE:-$HOME/.local/share/agent-config}"
AGENT_CONFIG="${AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/chezmoi/agent-config.json}"
MAD_ADAPTER="$MAD_SCRIPTS/paseo-mcp-adapter"
MAD_VALIDATE="$MAD_SCRIPTS/manual-orchestration-validate"
MAD_PLAN_VALIDATE="$MAD_SCRIPTS/paseo-plan-dependency-validate"
MAD_REVIEW_BUNDLE="$MAD_SCRIPTS/review-bundle"
MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"
MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"
MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"
MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"
MAD_GENERATOR="${MAD_GENERATOR:-$HOME/.local/bin/agent-config}"
PROJECT_ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)}"
```

`MAD_STATE_DIR` は run directory と worktree の置き場所を決める根であり、親は export せずこの初期化だけで値を決める。`mad-worktree` と `mad-progress` は、環境変数が未設定なら `$HOME/.local/state/mad` を既定値として使う。

`tests/manual/paseo-unit-gate.sh` はこの repository の checkout 専用である。別repositoryのMADでは、そのrepository固有のgateを使い、存在しなければこのmigration gateを実行しない。

## provider と model の解決

親はまず、Task 5 の exporter が生成した export を配布 module で検証する。

```bash
MAD_SHARE="$HOME/.local/share/agent-config"
node -e 'const c=require(process.argv[1]); c.writeResolvedExport0600(process.argv[2], process.argv[3])' \
  "$MAD_SHARE/mad-contract.js" "$AGENT_CONFIG" "$RUN_DIR/resolved-export.json"
node -e 'const c=require(process.argv[1]); c.writeProviderEnumeration0600(process.argv[2], process.argv[3])' \
  "$MAD_SHARE/mad-contract.js" "$RUN_DIR/resolved-export.json" "$RUN_DIR/provider-enumeration.json"
```

`provider-enumeration.json` の provider ID 集合だけを discovery の入力にする。親は adapter の `list-providers` を一回呼び、列挙集合と `available: true` の集合の積集合に対して `list-models --provider <id>` を一回ずつ呼ぶ。未選択の provider に model discovery を行わない。adapter は discovery と wait/stop の transport と応答の strict な形の境界であり、親は raw response、account metadata、credential、URL を保存しない。adapter は create の subcommand を持たない。

各 response を検査してから、mode 0600 の regular file として保存する。`mad-contract.js` の `writeAvailabilitySnapshot0600` は列挙集合を snapshot の入力集合にし、available でない provider の models を空配列にする。snapshot が不正、欠落、書き込み失敗のときは create を行わず、run の `state` と `phase_state` を `waiting_for_user` にする。

snapshot の保存後、親は次の `agent-config resolve` のみで launch を解決する。

```bash
"$MAD_GENERATOR" --input "$AGENT_CONFIG" resolve \
  --project "$PROJECT" --role "$ROLE" --provenance "$PROVENANCE" \
  --complexity "$COMPLEXITY" --round "$ROUND" \
  --snapshot "$RUN_DIR/snapshot.json" > "$RUN_DIR/launch.json"
```

`$PROVENANCE` に入れる値は子の役目で決める。implement とそれ以外の初回の子は `mad-dispatch`、
指摘を修正する子は `mad-fix`、再レビューの子は `mad-review` を渡す。`$COMPLEXITY` には
プランのタスクの `**Complexity:**` の値を入れ、行が無いタスクでは `routine` を入れる。
`$ROUND` には review/fix loop のラウンド番号を入れ、review/fix loop の外で起動する子には
`0` を入れる。`mad-fix` で `$ROUND` が 2 以上のとき、CLI が複雑度を 1 段上げる。

成功時の stdout は `mad-launch-spec` 一件で exit 0、候補が尽きたときは `mad-launch-failure` 一件で exit 4、入力または snapshot が不正なときは exit 2 である。exit 4 は `waiting_for_user`、exit 2 は `failed` として create を行わない。成功 launch は strict に検査し、`modeId` が `auto` でないもの、allowlist に無い feature、宣言型と違う scalar、整数でない整数 feature を拒否する。

environment は親の AI 環境名も見て決まる。CLI と runner はどちらも `AGENT_ENV` だけを読む。`AGENT_ENV_SESSION` は参照しない。`AGENT_ENV` は Paseo の provider record が子へ注入する名前なので、Paseo が起動した子では必ず正しい値になる。`AGENT_ENV` が未設定または空文字なら、親の AI 環境名は無いものとして扱う。親の AI 環境名が正本の `environments` に無い名前なら、`resolve` は exit 2 で終わる。runner は create の直前に launch spec の `environment` と親の AI 環境名を比べる。2 つが食い違うときは `mcp-create.json` を書かずに `waiting_for_user` で止まるので、親は `mcp__paseo__create_agent` を呼ばない。

## create request と state

implementer create の順序は `task 抜粋` → `execution context の検証と enrichment` → `request build と contract assert` → `create 前の prepare` → `親の公式 mcp__paseo__create_agent` → `response の sanitization` で固定する。

initial attempt と fix attempt の implementer には、create request の組み立てより先に専用の attempt directory で次を実行する。

```bash
ATTEMPT_BASE="$(git -C "$WORKSPACE_CWD" rev-parse HEAD)"
"$MAD_TASK_BRIEF" "$PLAN_FILE" "$TASK_NUMBER" "$ATTEMPT_DIR/task-excerpt.md"
```

親は抽出直後に、次の required field を持つ `execution-context.md` を同じ attempt directory へ新規作成する。`RUN_ID`、`TASK_ID`、`TASK_NUMBER`、`ATTEMPT_ID`、`PHASE`、`ROLE_PROMPT`、`ROLE_SCHEMA`、`ATTEMPT_BASE`、`WORKSPACE_CWD`、`ROUND`、`RESULT_PATH`、`HANDOFF_PATH`、`LOG_PATH`、`DECISION_REQUEST_PATH`、`CONSTRAINTS_FILE`、`REVIEW_SCOPE_PATH`、`OPEN_FINDINGS_PATH` はすべて必須である。path field は absolute path とし、`ATTEMPT_BASE` は attempt 開始時に上のコマンドで固定した immutable SHA とする。context には role prompt と schema を必ず読むこと、global constraints である `CONSTRAINTS_FILE` を守ること、各 destination へ成果物を書くことを明記する。

`initial` では `REVIEW_SCOPE_PATH` と `OPEN_FINDINGS_PATH` を `not-applicable` とする。`fix` では両方を既存の mode `0600` regular file の absolute path とし、review scope の allowed files だけを変更して open findings だけを解消する指示を context に含める。`PHASE` とこの分岐が一致しない context は拒否する。

親は `execution-context.md` の検証後、その全文と `task-excerpt.md` の task 抜粋だけをこの順に合成して `brief.md` を作る。`task-excerpt.md`、`execution-context.md`、composed `brief.md` は各 attempt で fresh な mode `0600` の regular file とし、既存 path への上書きや別 attempt の context または brief を再利用しない。full plan は合成しない。`brief.md` の absolute path だけを `initialPrompt` に渡し、prose や role/schema path を request へ追加しない。role/schema 情報は brief の context が child へ伝える。

required field の欠落・型または absolute path の不正、task 抽出、enrichment または write に失敗した場合は attempt を `failed` にして `buildMadCreateRequestV1` と `--prepare-create` を実行せず、create を呼ばない。auditor と reviewer はこの brief-only dispatch の対象外であり、それぞれの役割に必要な prompt、schema、入力成果物を渡せる。

launch の検証後、親は `buildMadCreateRequestV1` を使って次の 6 つの top-level key だけを持つ request を作る。key は公式 MCP tool の引数と一対一に対応する。

```text
title, workspaceId, initialPrompt, notifyOnFinish, provider, settings
settings: modeId, thinkingOptionId, features
```

`provider` は `<launch.provider>/<launch.model>`、`settings.modeId` は厳密に `auto`、`settings.features` は launch の `featureValues` そのものである。`claude` と `codex` は `fast_mode` の `true`/`false` をここに載せられる。builder が成功するまで request file を作らない。成功した request は `writeMadCreateRequest0600` で同じ directory に atomic rename し、`mcp-create.json` という mode 0600 の regular file とする。runner はここで停止し、create の transport を実行しない。

親は `mcp-create.json` を読み、`assertMadCreateRequestV1` で再検証してから、その 6 key をそのまま `mcp__paseo__create_agent` の引数に渡す。検証を通していない request で create を呼ばない。Paseo CLI の `run` は `settings.features` を渡す option を持たないので、CLI を create の経路に使わない。

create の直前の検証は次で行う。state、call log、消費 marker のいずれも変更しない。

```bash
"$MAD_VALIDATE" --assert-create-request \
  --share-dir "$MAD_SHARE" --attempt-dir "$ATTEMPT_DIR"
```

この assertion は `mcp-create.json` が mode 0600 の regular file であること、重複 key が無いこと、`MadCreateRequestV1` の exact key set であること、`settings.modeId` が `auto` であること、`settings.features` が launch の provider の allowlist に収まり `featureValues` と一致すること、`provider` が `<launch.provider>/<launch.model>` であることを確認する。exit 2 のときは create を呼ばない。

`--assert-create-request` は検証だけを行い、marker を作らない。検証を通ったことは、create を呼ぶ権利にはならない。同じ attempt を見る 2 つの親が同時にこの assertion を通れば、`mcp__paseo__create_agent` を 2 回呼べてしまう。そのため、create を呼ぶ直前には次の `--prepare-create` を必ず通す。

```bash
"$MAD_VALIDATE" --prepare-create \
  --share-dir "$MAD_SHARE" --attempt-dir "$ATTEMPT_DIR"
```

create は attempt ごとに一回だけである。`--prepare-create` は `--assert-create-request` と同じ request の strict 検証に加えて、attempt state が厳密に `{"state":"pending","create_accepted":false}` の 0600 regular file であること、call log が `MadCallLogV1` を満たし `create_agent`、`wait_agent`、`stop_agent`、`failure` の event を持たないことを確認する。全て成功した後にだけ、mode 0600 の `mcp-create.prepared` を `O_EXCL` で作る。`--prepare-create` が成功した呼び出しだけが `mcp__paseo__create_agent` を呼べる。exit 2 のときは create を呼ばない。

検証に落ちた呼び出しは marker を残さず、state と call log も書き換えない。request が契約を満たさないときは marker が存在しないままである。marker を既に取られている二回目と同時実行の敗者も、marker、state、call log のどれも書き換えずに exit 2 で止まる。

`--exercise-accepted` は marker を作らない。`mcp-create.prepared` が 0600 の regular file で `{"version":1,"type":"mad-create-prepare","consumed":true}` の exact key set であることを確認し、attempt state と call log の受理前検査を通してから response を処理する。marker が無い、mode が違う、schema が違う、又は既に受理済みの attempt は、state と call log を一切書き換えずに exit 2 で拒否する。

create は child ごとに一回だけである。親は返ってきた response を `{"status":"accepted","childRef":"<safe-id>"}` の exact key set に縮約し、basename-safe opaque な `childRef` だけを保存する。raw response、activity、log、`inspect` 出力を state にも log にも残さない。attempt state は create 前に `create_accepted: false` を保存し、親は key set が厳密な accepted response の `childRef` を受け取ったときだけ `create_accepted: true`、`state: running`、`child_ref` を同時に保存する。この true は wait timeout/error、親の decision、`failed`、`waiting_for_user`、`unresolved`、`stopped`、`ok` を含む以後の全 state で保持し、child_ref を必須にする。受理前の discovery、resolve、request build、create の失敗は `create_accepted: false` かつ child_ref を持たない。欠損、未知 key、重複 key、型不正、不安全な ID、拒否、transport failure は `failed` とし、retry を行わない。

`notifyOnFinish` は `mcp__paseo__create_agent` が持つ引数なので、request の boolean をそのまま渡す。完了検知は accepted `childRef` を使う polling であり、親は adapter の `wait-agent --child-ref <safe-id> --timeout <seconds>` を child ごとに一つだけ呼ぶ。adapter は内部で wait の raw response の allowed key (`agentId`、`status`、`message`) と必須の `agentId` が childRef に一致することを検証してから `{"status":"idle"|"timeout"|"error"}` に縮約する。停止も親が直接 CLI/MCP を呼ばず、adapter の `stop-agent --child-ref <safe-id>` を使う。adapter は停止 response の allowed key (`stoppedCount`、`agentIds`)、`stoppedCount: 1`、`agentIds` の一件、および childRef との完全一致を検証してから `{"status":"stopped"}` に縮約し、transport または不正 response は `{"status":"error"}` だけを返す。wait/stop の status 以外の活動履歴・本文・raw response を state/log へ保存しない。

成功 run の call log は `mad-call-log` として discovery、create、wait、必要な stop の順序、回数、検証済み artifact path と縮約済み wait/stop status だけを記録する。実運用の state と log に prompt、request payload、raw adapter response、credential、auth/history、URL を入れない。fixture の匿名 call log だけが検証済み request payload を持てる。

`MadCallLogV1` は `{version:1,type:"mad-call-log",events:[...]}` である。event は `seq` と `operation` に加えて、次の表の key だけを持つ。`seq` は 0 から連続する整数であり、配列の index と一致する。宣言に無い key、宣言に無い `operation`、飛んだ `seq`、URL を含む値は exit 2 である。runner は書き込む前にこの検査を通す。

| operation | 追加 key |
|---|---|
| `enumerate_materialized_provider_ids` | `providerIds` |
| `list_providers` | `callCount`、`materializedProviderIds`、`availableProviderIds` |
| `list_models` | `callCount`、`provider` |
| `write_snapshot` | `path`、`mode`、`regularFile` |
| `resolve` | `exitCode`、`outputType`、`stdoutDocuments`、`environment`、`role`、`duty`、`complexity`、`requestedComplexity`、`provider`、`model`、`effort`、`features` |
| `build_create_request` | `path`、`mode`、`regularFile`、`topLevelKeys`、`settingsKeys`、`validatedBeforeWrite` |
| `create_agent` | `callCount`、`requestPath`、`transport` |
| `wait_agent` | `callCount`、`timeoutSeconds`、`status` |
| `stop_agent` | `callCount`、`status` |
| `failure` | `stage`、`exitCode`、`createCalls`、`state` |

`resolve` が exit 2 のときは `provider`、`model`、`effort`、`features`、`duty`、`complexity`、`requestedComplexity` に `null` を入れ、`environment` と `role` は親が渡した値を入れる。exit 4 のときは `mad-launch-failure` の値を入れ、`provider`、`model`、`effort`、`features` に `null` を入れる。`effort` には launch spec の `thinkingOptionId` の値を入れる。

`create_agent.transport` は `mcp__paseo__create_agent` の一語に固定する。create の経路が公式 MCP tool だけであることを、この値が証跡として示す。

run の対応は次で固定する。

| 事象 | state | create |
|---|---|---|
| discovery / model discovery / snapshot の失敗 | `waiting_for_user` | 0 回 |
| launch exit 4 | `waiting_for_user` | 0 回 |
| launch exit 2 / launch validation / request build の失敗 | `failed` | 0 回 |
| 親の AI 環境名と launch の環境の不一致 | `waiting_for_user` | 0 回 |
| prepare の失敗（request 不正、state が pending でない、log に create 以後の event、marker 済み） | 変更しない | 0 回 |
| 受理前検査の失敗（prepare marker が無い、mode 不正、schema 不正、既に受理済み） | 変更しない | 0 回 |
| `mcp-create.json` の検証失敗 | `failed` | 0 回 |
| create の拒否 / accepted response の契約違反 | `failed` | 1 回 |
| create 受理 | `running` | 1 回 |
| 子の decision request | `unresolved` | 親が停止 |

implementer の終了後、親は `status` で分岐する。`DONE` と `DONE_WITH_CONCERNS` だけ、採用前に次の post-commit check を実行する。

```bash
"$MAD_VALIDATE" --check-implement-result \
  --workdir "$WORKSPACE_CWD" --base "$ATTEMPT_BASE" --round "$ROUND" \
  --result-file "$RESULT_FILE"
```

成功した結果だけを採用候補にする。exit `2` なら validator の stderr の 1 行を理由として同一 run の decision request に転記し、run の `state` と `phase_state` を `waiting_for_user`、workspace の integration を `pending` のままにして archive しない。

`BLOCKED` または `NEEDS_CONTEXT` では post-commit check を実行しない。result の `summary` と、non-null の `decisionRequestPath` が指す質問・選択肢の内容を同一 run の decision request に転記し、run の `state` と `phase_state` を `waiting_for_user` にする。この場合も workspace の integration は `pending` のままにして archive しない。status と `decisionRequestPath` の組み合わせが契約に反する結果は採用せず `waiting_for_user` にする。

## delivery role map

MAD の delivery role は次の 4 役である。各 role は同名の `agent-defs/prompts/<role>.md` と `agent-defs/schemas/<role>.json` を持ち、正本の `agentRoles` に同じ key で登録する。

| role | 責務 |
|---|---|
| `implementer` | 実装と検証 |
| `task-reviewer` | task 単位の spec / quality review |
| `re-reviewer` | fix diff の指摘判定 |
| `final-reviewer` | branch 全体の最終 review |

`plan-auditor` は delivery role ではなく、同じ prompt/schema 命名規則を使う実装前の one-shot gate である。

親は auditor と reviewer の role prompt と schema の absolute path を `initialPrompt` に含め、子の JSON を `result.json` と `handoff.json` の artifact path へ保存する。implementer の initial/fix attempt は前述の fresh `brief.md` だけを渡す。read role の `access` は prompt と artifact contract の情報だけを示し、Paseo mode を変更しない。

## review/fix の上限と scope

review/fix loop は task ごとに **max_rounds は 4** とする。round `0` は task-reviewer の初回 review、round `1` から `3` は同じ task scope の fix と re-review であり、4 ラウンドで解決しない finding、または新しい hotfix node はこの run で扱わない。上限到達時は `unresolved` として停止し、新しい fix/review を起動しない。

親は review 開始前に mode `0600` の `mad-review-scope` を一つ作る。scope は `task`、repository-relative な `allowedFiles`、初回 review が扱う `findingIds`、最終確認へ渡す絶対 `outOfScopePath` だけを持つ。run state の `review_policy` は `max_rounds: 4`、scope file、out-of-scope observations path を固定し、fix の `changedFiles` は `allowedFiles` の部分集合でなければならない。`findingIds` は round 0 の review を始める前に確定する immutable な値であり、round 0 の review が出した finding ではない。親が round 0 より前に指す finding を持たないなら空配列にする。round 0 以降の未解決の指摘は `mad-review-open-findings` が持つ。

review/fix child を create する前に、必ず次を実行する。

```bash
"$MAD_VALIDATE" --prepare-review \
  --run-dir "$RUN_DIR" --task "$TASK_ID" --phase review \
  --node "$TASK_ID-review" --attempt "$ATTEMPT_ID" --scope-file "$SCOPE_FILE"
```

fix は `--phase fix --node "$TASK_ID-fix"`、re-review は `--phase re-review --node "$TASK_ID-re-review"` とし、同じ scope marker を使う。admission が失敗したら `mcp__paseo__create_agent` を呼ばない。親は fix 後に `"$MAD_VALIDATE" --check-review-scope --scope-file "$SCOPE_FILE" --result-file "$RESULT_FILE"` を実行し、scope 外なら fix を採用しない。

レビュー child を create する前に、親は review package を組み立てる。組み立ては 1 本のスクリプトに任せ、header の形が 2 か所で食い違わないようにする。

```bash
"$MAD_REVIEW_BUNDLE" \
  --cwd "$WORKSPACE_CWD" --base "$PACKAGE_BASE" --head "$PACKAGE_HEAD" \
  --out "$ATTEMPT_DIR/review-package.diff"
```

`PACKAGE_BASE` と `PACKAGE_HEAD` は役ごとに次で決める。MAD の親は `--force` を渡さない。attempt directory は round ごとに分かれるので、既存ファイルがあることは範囲の取り違えを意味する。

- round 0 の `task-reviewer` は、run state が持つ確定した `base` を `PACKAGE_BASE`、実装役が commit した後の `HEAD` を `PACKAGE_HEAD` とする
- round 1 から 3 の `re-reviewer` は、そのラウンドの fix を始める直前の `HEAD` を `PACKAGE_BASE`、fix を commit した後の `HEAD` を `PACKAGE_HEAD` とする。`HEAD~1` を使わない。1 ラウンドが複数の commit になったとき、最後の commit 以外が範囲から外れる
- `final-reviewer` は、run state が持つ確定した `base` を `PACKAGE_BASE`、全 task 完了後の `HEAD` を `PACKAGE_HEAD` とする

親は `task-reviewer`、`re-reviewer`、`final-reviewer` の 3 つの結果を採用する前に、`--check-review-package` で範囲を検査する。`task-reviewer` と `re-reviewer` の結果には、範囲に加えて `--check-review-verdict` で verdict も検査する。`final-reviewer` の結果は範囲だけを検査する。`--check-review-verdict` が受け付ける `--role` は `task-reviewer` と `re-reviewer` の 2 つだけであり、`final-reviewer` を渡すと exit 2 で拒む。検査のいずれかが失敗したらその結果を採用せず、attempt を `failed` にする。

```bash
"$MAD_VALIDATE" --check-review-package \
  --package-file "$ATTEMPT_DIR/review-package.diff" --result-file "$RESULT_FILE"
"$MAD_VALIDATE" --check-review-verdict \
  --result-file "$RESULT_FILE" --role task-reviewer
```

`re-reviewer` の結果には、`--check-review-verdict` へ `--role re-reviewer --open-findings-file "$RUN_DIR/review-open-findings/$TASK_ID-round-$ROUND.json"` を渡す。`final-reviewer` の結果には `--check-review-package` だけを実行する。

round 0 のレビュー結果を採用したあと、親は次の 4 段階を順に行う。順序を入れ替えない。第 3 段階より先に第 4 段階を呼ぶと、一覧がまだ無いので検査が失敗する。

1. `--check-review-package` と `--check-review-verdict --role task-reviewer` で round 0 の結果を検査して採用する
2. `cannotVerify` を 1 件ずつ解消し、`<run-dir>/review-cannot-verify/<task>.json` を mode 0600 で書く。`resolution` は `confirmed_gap`、`satisfied`、`deferred` のいずれかとし、`deferred` の `item` は `outOfScopePath` の observations の `items[].summary` に同じ文字列が無ければならない
3. round 1 の未解決の指摘の一覧を作る

```bash
"$MAD_VALIDATE" --open-review-findings \
  --run-dir "$RUN_DIR" --scope-file "$SCOPE_FILE" --result-file "$RESULT_FILE" \
  --cannot-verify-file "$RUN_DIR/review-cannot-verify/$TASK_ID.json"
```

`--cannot-verify-file` は round 0 の結果の `cannotVerify` が非空のときだけ渡す。

4. 記録と一覧の対応を検査する

```bash
"$MAD_VALIDATE" --check-review-cannot-verify \
  --run-dir "$RUN_DIR" --scope-file "$SCOPE_FILE" --result-file "$RESULT_FILE"
```

未解決の指摘の一覧は `<run-dir>/review-open-findings/<task>-round-<round>.json` に mode 0600 で置く。`findings` が空配列のときも一覧を必ず書き、fix ループへ入らなかった判断を記録に残す。一覧が空なら親は fix ラウンドの admission を取らず、そのタスクを閉じる。指摘の `id` は `OF-` から始める書式とし、同じ task で一度使った `id` を別の指摘へ割り当てない。

round `N` の `re-reviewer` の結果を採用したら、次のラウンドの一覧を親ではなくコードに計算させる。

```bash
"$MAD_VALIDATE" --advance-review-findings \
  --run-dir "$RUN_DIR" --scope-file "$SCOPE_FILE" --result-file "$RESULT_FILE" --round "$ROUND"
```

親が未解決の指摘を散文で引き継がない。summary の言い換えで指摘が記録から失われる。

spec 外などで見つけた重要事項は、fix の対象へ追加せず `mad-review-observations` として `outOfScopePath` に 0600 で保持する。review/fix 中はそれを理由に新しい fix/review を起動しない。最終 gate で一度だけ decision request に列挙し、ユーザーが scope 拡張を承認した場合は元 run を再利用せず、新しい task/run として開始する。

観測は次で atomic に保存する。

```bash
"$MAD_VALIDATE" --write-review-observations \
  --scope-file "$SCOPE_FILE" --observation-file "$OBSERVATION_FILE" \
  --input "$OBSERVATION_INPUT"
```

観測ファイルは最終 gate 前に次で検査する。

```bash
"$MAD_VALIDATE" --check-review-observations \
  --scope-file "$SCOPE_FILE" --observation-file "$OBSERVATION_FILE"
```

## plan dependency gate

plan の Task 番号、`Depends on`、`Files:` の literal path は次で検証する。

```bash
"$MAD_PLAN_VALIDATE" "$PLAN_FILE"
"$MAD_PLAN_VALIDATE" --waves "$PLAN_FILE"
```

最初のコマンドは plan を検証し、存在しない Task の参照、循環、同じ wave の Files 衝突があれば exit 2、問題が無ければ stdout 空で exit 0 になる。検証成功後だけ `--waves` を実行し、その出力を実装順序の正本にする。wave 内の implementer は並列に create できるが、wave の全 task の採用と merge が完了するまでは次の wave の workspace または implementer を create しない。

## run と attempt の状態

親は一意な run ID を発行し、作業ツリーの外にある run directory に `state.json` を置く。child の成果物は必ず `nodes/<node-id>/attempts/<attempt-id>/` に分け、`prompt.md`、implementer 用の `task-excerpt.md`、`execution-context.md`、`brief.md`、`result.json` または `result.md`、`state.json`、`handoff.json`、`log.md` を置く。node 直下へ成果物を置かず、同じ node を再実行するときも既存 attempt を上書きしない。

run state は `run_id`、`recipe`、`state`、`phase`、`phase_state`、`next_action`、`current_round`、`started_at`、`finished_at`、`backend`、`backend_reason`、`parent_decision`、`active_nodes`、`completed_nodes`、`adopted_attempts`、`artifact_paths` を持つ。review/fix を含む run はさらに `review_policy`（`max_rounds: 4`、`scope_file`、`out_of_scope_path`）を持つ。worktree を作る run は確定した `base` も持つ。attempt state は `run_id`、`node`、`attempt`、`round`、`state`、`phase`、`phase_state`、`next_action`、`started_at`、`finished_at`、`create_accepted`、`child_ref`、`backend`、`backend_reason`、`parent_decision` を持ち、review/fix attempt は発行済みの `review_admission` absolute path も持つ。

`state` は `pending`、`running`、`waiting_for_user`、`ok`、`failed`、`stopped`、`unresolved` のいずれかである。`state` が `running` の attempt は UTC ISO 8601 の `started_at` と `create_accepted: true` を必須にする。`create_accepted` は必須 boolean である。false なら child_ref を持たず、true なら state を問わず basename-safe な child_ref を必須にする。`adopted_attempts` は node ID から親が採用した attempt ID への map とし、run を `ok` にする前に採用結果を確認する。

`handoff.json.artifact_paths` には子が返した絶対 path の regular file だけを入れる。親は `state.json` と handoff の path を確認し、子の本文を会話へ転記しない。実運用の state、handoff、log は mode 0600 とし、credential、auth/history、raw response、prompt の値を保存しない。

## child の起動と完了検知

child の role、prompt、schema、workspace を決めた後、親は `mcp-create.json` を検証してから `mcp__paseo__create_agent` を一回だけ呼ぶ。`provider`、`settings.modeId`、`settings.thinkingOptionId`、`settings.features`、`notifyOnFinish` は launch と create request の検証済み値を使い、値を作り直さない。auditor と reviewer の `initialPrompt` には役割に必要な prompt file、schema file、入力成果物の absolute path を含める。implementer の initial/fix attempt では、検証済み execution context と task 抜粋を合成した専用の fresh `brief.md` の absolute path だけを `initialPrompt` に入れる。

起動後は child ごとに一つだけ見張りを置く。Paseo MCP の child は adapter の `wait-agent` を使う。返ってきた縮約済み status は一語だけを採用し、活動履歴や本文を親の log へ流さない。通知を先に受け取った場合は見張りを止め、成果物を確認する。出力が無いまま idle なら同じ backend で親が再指示を判断できるが、timeout、error、unknown は `waiting_for_user` として停止する。停止が必要なときは adapter の `stop-agent --child-ref <safe-id>` を一回だけ呼び、返った縮約済み stop status と 0600 の state/evidence だけを読む。

1 attempt につき create と見張りは一つだけである。create の transport failure、拒否、状態不明を別経路で補完せず、親が `failed`、`waiting_for_user`、`stopped` のいずれかを記録する。停止も adapter 以外の経路を使わず、stop の縮約結果を記録してから `stopped` を確定する。

## worktree と diff

`implement` と `spike` は child ごとに Paseo workspace を先に作る。workspace は `isolation: worktree`、`mode: branch-off`、呼び出し元 path、`mad/<run-id>/<node-id>` の branch、確定した base を持つ。返った `workspaceId` を create request に渡し、absolute `cwd` と branch を `workspaces.json` に記録する。workspace は node ごとに一つであり、既存の台帳 entry を別 ID で上書きしない。

レビュー child には worktree の中身を直接読ませず、親が `"$MAD_REVIEW_BUNDLE"` を呼んで attempt の `review-package.diff` を作り、その絶対 path だけを渡す。review package の組み立ては workspace archive より前に行う。組み立ての失敗は run を `failed` とし、空の diff は親が判断する。workspace の integration は `pending`、`merged`、`declined` のいずれかで、`declined` には理由を残す。integration の判断後にだけ archive し、`archived: true` を台帳へ書く。

各 wave の採用済み task は task number の昇順で、呼び出し元の `PROJECT_ROOT` に統合する。

```bash
git -C "$PROJECT_ROOT" merge --no-ff "mad/<run-id>/<node-id>"
```

merge 成功時だけ workspace の integration を `merged` にする。衝突したら直ちに `git -C "$PROJECT_ROOT" merge --abort` を実行し、integration を `pending` のままにして archive しない。run の `state` と `phase_state` を `waiting_for_user` にし、decision request へ衝突ファイルの repository-relative path、衝突した 2 task の番号、両 task の `Depends on` と `Files:` を書く。同一 wave の残りの merge と、後続 wave の create は停止する。

## recipe と判断要求

`research`、`decide`、`debate`、`fanout`、`review`、`triage` は独立 child を並列に起動し、全 child が `ok` になってから親が統合 child を一つ起動する。`spec`、`plan`、`implement`、`refine` は `max_rounds` を親が管理する。各 round の開始、成果物、parent decision、終了状態を state に残し、上限到達時に成功扱いにせず `unresolved` とする。

child が判断を要求する場合、write role は `decisionRequestPath` として absolute path を返し、read role は構造化された `decisionRequest` を返す。親は質問、選択肢、推す案と理由、確認済みのことをそのまま decision request に記録し、run の `state` と `phase_state` を `waiting_for_user` にする。回答後は同じ node に新しい attempt を発行し、既存 attempt を上書きしない。回答が無い場合は `stopped` として停止する。

親はフェーズ境界で child の state と成果物を確認する。失敗 child を隠して統合せず、レビュー、再実行、停止、user decision のいずれかを明示的に state へ記録する。delivery は spec、plan、implement、review、final-review の境界を順に進み、4 つの delivery role の prompt と schema を同じ artifact contract で使う。

## validator と後片付け

親は child の実行 backend と切り離して成果物 validator を実行する。validator は MCP を呼ばず、state、attempt、handoff、workspace、artifact path の形だけを確認する。完了 recipe に必要な node の adopted attempt、regular file、integration、archive を確認し、失敗した run を `ok` にしない。

integration の判断と diff の保存が完了したら、親は workspace を Paseo MCP で archive し、台帳に `archived: true` を記録する。archive に失敗しても run directory と台帳は削除しない。`pending` の integration や未 archive workspace が残る run は `ok` にしない。
