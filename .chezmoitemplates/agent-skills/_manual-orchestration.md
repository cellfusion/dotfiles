# Paseo MAD の共通契約

MAD の実行 backend は `paseo-mcp` だけである。親は Paseo MCP の discovery、model discovery、agent create、state の記録を担当し、子の本文を会話へ転記しない。利用できない場合は run を開始せず `waiting_for_user` として停止する。開始後に別の backend へ切り替えたり、別の transport を試したり、同じ create を retry したりしてはならない。

## provider と model の解決

親はまず、Task 5 の exporter が生成した export を配布 module で検証する。

```bash
MAD_SHARE="$HOME/.local/share/agent-config"
node -e 'const c=require(process.argv[1]); c.writeResolvedExport0600(process.argv[2], process.argv[3])' \
  "$MAD_SHARE/mad-contract.js" "$AGENT_CONFIG" "$RUN_DIR/resolved-export.json"
node -e 'const c=require(process.argv[1]); c.writeProviderEnumeration0600(process.argv[2], process.argv[3])' \
  "$MAD_SHARE/mad-contract.js" "$RUN_DIR/resolved-export.json" "$RUN_DIR/provider-enumeration.json"
```

`provider-enumeration.json` の provider ID 集合だけを discovery の入力にする。親は adapter の `list-providers` を一回呼び、列挙集合と `available: true` の集合の積集合に対して `list-models --provider <id>` を一回ずつ呼ぶ。未選択の provider に model discovery を行わない。adapter は MCP transport と応答の strict な形の境界であり、親は raw response、account metadata、credential、URL を保存しない。

各 response を検査してから、mode 0600 の regular file として保存する。`mad-contract.js` の `writeAvailabilitySnapshot0600` は列挙集合を snapshot の入力集合にし、available でない provider の models を空配列にする。snapshot が不正、欠落、書き込み失敗のときは create を行わず、run の `state` と `phase_state` を `waiting_for_user` にする。

snapshot の保存後、親は次の CLI のみで launch を解決する。

```bash
generate-paseo-config --input "$AGENT_CONFIG" resolve \
  --project "$PROJECT" --role "$ROLE" --provenance mad-dispatch \
  --snapshot "$RUN_DIR/snapshot.json" > "$RUN_DIR/launch.json"
```

成功時の stdout は `mad-launch-spec` 一件で exit 0、候補が尽きたときは `mad-launch-failure` 一件で exit 4、入力または snapshot が不正なときは exit 2 である。exit 4 は `waiting_for_user`、exit 2 は `failed` として create を行わない。成功 launch は strict に検査し、`modeId` が `auto` でないもの、allowlist に無い feature、宣言型と違う scalar、整数でない整数 feature を拒否する。

## create request と state

launch の検証後、親は `buildMadCreateRequestV1` を使って次の 6 つの top-level key だけを持つ request を作る。

```text
title, workspaceId, initialPrompt, notifyOnFinish, provider, settings
settings: modeId, thinkingOptionId, features
```

`provider` は `<launch.provider>/<launch.model>`、`settings.modeId` は厳密に `auto` である。builder が成功するまで request file を作らない。成功した request は `writeMadCreateRequest0600` で同じ directory に atomic rename し、mode 0600 の regular file とする。親は adapter の `create-agent --request <absolute-0600-json-file>` を一回だけ呼ぶ。adapter は Paseo CLI の `run --background --json` が返す厳密な `{agentId,status,provider,cwd,title}` response を検証し、basename-safe opaque `agentId` だけを `childRef` として `{"status":"accepted","childRef":"<safe-id>"}` に縮約する。親は key set が厳密な accepted response の `childRef` を受け取ったときだけ run を `running` にし、attempt state の `child_ref` にその値を保存する。欠損、未知 key、重複 key、型不正、不安全な ID、拒否、transport failure は `failed` とし、retry を行わない。

Paseo CLI に `notifyOnFinish` 専用 option はないため、adapter は request の boolean を metadata label `notifyOnFinish=true` または `notifyOnFinish=false` に一対一で転送する。この label は notification の配送保証ではない。完了検知は常に accepted `childRef` を使う polling であり、`paseo wait <childRef> --timeout <seconds> --json` を child ごとに一つだけ実行する。親が停止するときは同じ ID に `paseo stop <childRef> --json` を使う。wait/stop の status 以外の活動履歴・本文・raw response を state/log へ保存しない。

成功 run の call log は `mad-call-log` として discovery から create までの順序、回数、検証済み artifact path を記録する。failure の終端 event は stage、exit code、create 回数、state だけを記録する。実運用の state と log に prompt、request payload、raw adapter response、credential、auth/history、URL を入れない。fixture の匿名 call log だけが検証済み request payload を持てる。

run の対応は次で固定する。

| 事象 | state | create |
|---|---|---|
| discovery / model discovery / snapshot の失敗 | `waiting_for_user` | 0 回 |
| launch exit 4 | `waiting_for_user` | 0 回 |
| launch exit 2 / launch validation / request build の失敗 | `failed` | 0 回 |
| create の拒否 / transport failure | `failed` | 1 回 |
| create 受理 | `running` | 1 回 |
| 子の decision request | `unresolved` | 親が停止 |

## delivery role map

MAD の delivery role は次の 4 役である。各 role は同名の `agent-defs/prompts/<role>.md` と `agent-defs/schemas/<role>.json` を持ち、正本の `agentRoles` に同じ key で登録する。

| role | 責務 |
|---|---|
| `implementer` | 実装と検証 |
| `task-reviewer` | task 単位の spec / quality review |
| `re-reviewer` | fix diff の指摘判定 |
| `final-reviewer` | branch 全体の最終 review |

親は role の prompt と schema の絶対 path を子の `initialPrompt` に含め、子の JSON を `result.json` と `handoff.json` の artifact path へ保存する。read role の `access` は prompt と artifact contract の情報だけを示し、Paseo mode を変更しない。

## plan dependency gate

plan の Task 番号、`Depends on`、`Files:` の literal path は次で検証する。

```bash
paseo-plan-dependency-validate "$PLAN_FILE"
```

存在しない Task の参照、循環、同じ wave の Files 衝突があれば exit 2、問題が無ければ stdout 空で exit 0 である。plan を検証できないときは後段の child を起動しない。

## run と attempt の状態

親は一意な run ID を発行し、作業ツリーの外にある run directory に `state.json` を置く。child の成果物は必ず `nodes/<node-id>/attempts/<attempt-id>/` に分け、`prompt.md`、`result.json` または `result.md`、`state.json`、`handoff.json`、`log.md` を置く。node 直下へ成果物を置かず、同じ node を再実行するときも既存 attempt を上書きしない。

run state は `run_id`、`recipe`、`state`、`phase`、`phase_state`、`next_action`、`current_round`、`started_at`、`finished_at`、`backend`、`backend_reason`、`parent_decision`、`active_nodes`、`completed_nodes`、`adopted_attempts`、`artifact_paths` を持つ。worktree を作る run は確定した `base` も持つ。attempt state は `run_id`、`node`、`attempt`、`round`、`state`、`phase`、`phase_state`、`next_action`、`started_at`、`finished_at`、`child_ref`、`backend`、`backend_reason`、`parent_decision` を持つ。

`state` は `pending`、`running`、`waiting_for_user`、`ok`、`failed`、`stopped`、`unresolved` のいずれかである。`state` が `running` の attempt は UTC ISO 8601 の `started_at` を必須にする。`child_ref` は `create_agent` が返す agent ID であり、子をまだ起動していない pending attempt 以外では必須である。`adopted_attempts` は node ID から親が採用した attempt ID への map とし、run を `ok` にする前に採用結果を確認する。

`handoff.json.artifact_paths` には子が返した絶対 path の regular file だけを入れる。親は `state.json` と handoff の path を確認し、子の本文を会話へ転記しない。実運用の state、handoff、log は mode 0600 とし、credential、auth/history、raw response、prompt の値を保存しない。

## child の起動と完了検知

child の role、prompt、schema、workspace を決めた後、親は `paseo-mcp-adapter` の `create-agent --request` を呼ぶ。`provider`、`settings.modeId`、`settings.thinkingOptionId`、`notifyOnFinish` は launch と create request の検証済み値を使う。`notifyOnFinish` は専用 CLI option ではなく metadata label に一対一で写す。system prompt と schema は role の prompt file と schema file の絶対 path を `initialPrompt` に含めて渡す。

起動後は child ごとに一つだけ見張りを置く。Paseo MCP の child は `paseo wait <agent-id> --timeout <seconds> --json` または対応する MCP の status を使う。返ってきた status は一語だけを採用し、活動履歴や本文を親の log へ流さない。通知を先に受け取った場合は見張りを止め、成果物を確認する。出力が無いまま idle なら同じ backend で親が再指示を判断できるが、timeout、error、unknown は `waiting_for_user` として停止する。

1 attempt につき create と見張りは一つだけである。create の transport failure、拒否、状態不明を別経路で補完せず、親が `failed`、`waiting_for_user`、`stopped` のいずれかを記録する。

## worktree と diff

`implement` と `spike` は child ごとに Paseo workspace を先に作る。workspace は `isolation: worktree`、`mode: branch-off`、呼び出し元 path、`mad/<run-id>/<node-id>` の branch、確定した base を持つ。返った `workspaceId` を create request に渡し、absolute `cwd` と branch を `workspaces.json` に記録する。workspace は node ごとに一つであり、既存の台帳 entry を別 ID で上書きしない。

レビュー child には worktree の中身を直接読ませず、親が `git -C <cwd> diff <base>...HEAD` の出力を attempt の `diff.patch` に保存し、その絶対 path だけを渡す。diff の取得は workspace archive より前に行う。取得失敗は run を `failed` とし、空の diff は親が判断する。workspace の integration は `pending`、`merged`、`declined` のいずれかで、`declined` には理由を残す。integration の判断後にだけ archive し、`archived: true` を台帳へ書く。

## recipe と判断要求

`research`、`decide`、`debate`、`fanout`、`review`、`triage` は独立 child を並列に起動し、全 child が `ok` になってから親が統合 child を一つ起動する。`spec`、`plan`、`implement`、`refine` は `max_rounds` を親が管理する。各 round の開始、成果物、parent decision、終了状態を state に残し、上限到達時に成功扱いにせず `unresolved` とする。

child が判断を要求する場合、write role は `decisionRequestPath` として absolute path を返し、read role は構造化された `decisionRequest` を返す。親は質問、選択肢、推す案と理由、確認済みのことをそのまま decision request に記録し、run の `state` と `phase_state` を `waiting_for_user` にする。回答後は同じ node に新しい attempt を発行し、既存 attempt を上書きしない。回答が無い場合は `stopped` として停止する。

親はフェーズ境界で child の state と成果物を確認する。失敗 child を隠して統合せず、レビュー、再実行、停止、user decision のいずれかを明示的に state へ記録する。delivery は spec、plan、implement、review、final-review の境界を順に進み、4 つの delivery role の prompt と schema を同じ artifact contract で使う。

## validator と後片付け

親は child の実行 backend と切り離して成果物 validator を実行する。validator は MCP を呼ばず、state、attempt、handoff、workspace、artifact path の形だけを確認する。完了 recipe に必要な node の adopted attempt、regular file、integration、archive を確認し、失敗した run を `ok` にしない。

integration の判断と diff の保存が完了したら、親は workspace を Paseo MCP で archive し、台帳に `archived: true` を記録する。archive に失敗しても run directory と台帳は削除しない。`pending` の integration や未 archive workspace が残る run は `ok` にしない。
