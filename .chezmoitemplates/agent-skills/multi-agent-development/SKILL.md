---
name: multi-agent-development
description: >-
  親エージェントが複数の子エージェントを組み合わせて手動でオーケストレーションするときに使う。
  spec の作成、plan の作成、plan の implement、review、その 4 つを通す delivery が対象である。
  観点を分けた調査、候補案の生成と採点、立場を分けた賛否、項目ごとの並行処理、
  多観点レビューも対象である。
  brainstorming、writing-plans、subagent-driven-development、executing-plans、
  requesting-code-review、receiving-code-review、verification-before-completion の委譲先である。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 親主導の MAD オーケストレーション

MAD は親エージェントが子エージェントを起動・監視し、フェーズごとに判断して進める。子同士の
本文は会話へ集めず、共通契約で定めた run 成果物を介して後段へ渡す。

親は backend 選択、状態遷移、子の制御、ユーザーとの質問・承認だけを担う。子は本文を親へ返さず、
正規成果物への絶対パスを含む `handoff.json` を残す。親は `state.json`、`handoff.json`、ユーザーへ
relay する decision / approval request だけを読む。

**中核**: 作業が MAD のレシピの形にはまるなら、親が並列化・統合・介入を管理する。はまらない
作業では従来どおり単独の subagent を使う。

## 開発ライフサイクル recipe

上位 recipe は下位 recipe を再利用して、本文作成をすべて子へ委譲する。各 phase の開始前後に親が
state と handoff を確認し、必要なら `waiting_for_user` にして質問または approval request を relay する。
backend は共通契約の selector で一度だけ選ぶ。開始済みの子が失敗した場合、親は同じ backend で再指示・
再実行・停止を裁定し、別 backend へ自動 fallback してはならない。

### delivery role map

論理上の責務名と実際に起動する role は以下のとおりである。manifest の `delivery_duties` が正本であり、
Paseo MCP と native subagent はともに同じ role と `mad-attempt-v1` を使う。`spec-author` と `plan-author` だけが
正規 spec / plan を書く。review 系は既存の読み取り role を再利用し、backend が構造化出力を attempt の
`result.json` と `handoff.json` へ保存する。

| 論理責務 | 起動する role |
|---|---|
| `spec-author` | `spec-author` |
| `spec-reviewer` / `plan-reviewer` | `reviewer` |
| `planner` / `task-graph-analyzer` | `plan-author` |
| `implementer` | `sdd-implementer` |
| `task-reviewer` / `re-reviewer` / `final-reviewer` | `sdd-task-reviewer` / `sdd-re-reviewer` / `sdd-final-reviewer` |
| `review-synthesizer` | `review-synthesizer` |

### `spec`

- 入力: ユーザーの目的、既知の制約、既存成果物の絶対パス。
- 子: 必要に応じて `researcher` を並列起動し、`spec-author` が設計案と spec を作成し、`spec-reviewer`
  が self-review する。
- gate: 子が判断を要するときは decision request を作成し、spec 完成後は親が spec approval request を
  relay する。
- 完了: 親が承認した正規 spec の絶対パスを run state の `artifact_paths` に記録する。spec 本文は親へ
  転記しない。

### `plan`

- 入力: 承認済み spec の絶対パス。
- 子: `plan-author` が実装 plan を作成し、`plan-reviewer` が実装可能性・検証計画・依存関係を review する。
- gate: 親は plan review の採用 attempt を確認し、plan approval request を relay する。
- 完了: 親が承認した正規 plan の絶対パスだけを handoff に記録する。承認前の run は
  `waiting_for_user` とする。

### `implement`

- 入力: 承認済み plan、spec、既存の SDD ledger の絶対パス。
- 子: `task-graph-analyzer` が wave を作り、`worktree` 隔離後に `implementer`、`task-reviewer`、
  `re-reviewer`、`final-reviewer` が実装・review・fix loop を担う。独立 task は並列に起動する。
  base の確定と worktree 隔離の手順は、共通契約の「base の確定」と「worktree 隔離」に従う。
- gate: 親は wave と retry 上限、失敗・競合・例外だけを裁定する。task の本文、実装、review は作らない。
- 完了: 採用 attempt の実装成果物・検証記録・final review を handoff し、未解決で `max_rounds` に達した
  run は `unresolved` として停止する。

### `review`

- 入力: requirements、review package、対象成果物の絶対パス。
- 子: 観点別 `reviewer` を並列起動し、`review-synthesizer` が採用可能な指摘を統合する。ブランチ全体を
  merge 前に判定する場合だけ `final-reviewer` を使う。
- gate: 親は各 review attempt と統合前の handoff を確認し、要件変更または追加 review が必要なら
  user gate を relay する。
- 完了: 最終 review 成果物の絶対パスを handoff し、失敗 review を隠して完了にしてはならない。

### `delivery`

- 入力: ユーザーの目的と、存在するなら正規 spec / plan / ledger の絶対パス。
- 子: `spec`、`plan`、`implement`、`review` を順に起動し、必要な下位 recipe の子が各成果物を作る。
- gate: `spec → plan → implement ↔ review → final-review` の phase 境界で、親だけが user approval、継続、
  retry、停止を状態遷移として記録する。
- 完了: `final-review` node の採用 handoff と正規成果物の絶対パスを確認したときだけ delivery run を `ok` にする。

## 9 レシピの親主導フロー

役割や backend は共通契約に従って親が実行開始時に選ぶ。各レシピは、表に書いた並列子を起動した
後に親が確認する。`failed` または `stopped` の子があれば親が判断するまで統合・裁定を停止し、
成功した成果物だけを勝手に後段へ渡してはならない。

| レシピ | 用途と並列に起動する子 | 親が確認する境界 | 後段への handoff と失敗時 |
|---|---|---|---|
| `research` | 観点別の調査役を並列に起動する。既定観点: 現状と確認済みの事実、制約とリスク、代替案。`perspectives` で全 3 観点を差し替えられる。調査役は `researcher`、統合役は `synthesizer`。 | 調査役全件の `state.json` と成果物を親が確認する。 | 親の許可後だけ統合役へ調査成果物の絶対パスを渡す。失敗なら統合を停止する。 |
| `decide` | 候補案ごとの候補生成役を並列に起動する。 | 親が候補・評価基準・各子の状態を確認する。 | 親が確認した候補成果物の絶対パスだけを judge へ渡す。失敗なら裁定を停止する。 |
| `debate` | 立場ごとの賛成・反対・代替案の論者を並列に起動する。 | 親が立場の網羅性と各論者の状態を確認する。 | 親が確認した論者成果物の絶対パスだけを judge へ渡す。失敗なら裁定を停止する。 |
| `fanout` | item ごとの作業役を並列に起動する。 | 親が item ごとの完了状態と成果物を確認する。 | 親が確認した item 成果物の絶対パスだけを統合役へ渡す。失敗 item があれば統合を停止する。 |
| `review` | 観点別のレビュー役を並列に起動する。 | 親がレビュー観点、各指摘、各子の状態を確認する。 | 親が確認したレビュー成果物の絶対パスだけを最終レビュー役へ渡す。失敗なら最終統合を停止する。 |
| `triage` | item ごとの分類・優先順位付け役を並列に起動する。 | 親が分類基準、各 item の状態、保留項目を確認する。 | 親が確認した分類成果物の絶対パスだけを統合役へ渡す。失敗ならトリアージ統合を停止する。 |
| `implement` | 独立した作業単位ごとの実装役を、複数ある場合は並列に起動する。node ごとに worktree を作る。 | 親が実装成果物・テスト結果・各子の状態を確認する。 | 親が確認した実装成果物の絶対パスだけをレビュー役へ渡す。失敗ならレビューと次ラウンドを停止する。 |
| `spike` | 方針ごとの試作・検証役を並列に起動する。node ごとに worktree を作る。 | 親が比較基準、試作結果、各子の状態を確認する。 | 親が確認した試作成果物の絶対パスだけを judge へ渡す。失敗なら裁定を停止する。 |
| `refine` | 改稿役を起動した後、批評観点ごとの批評役を並列に起動する。 | 親が改稿物、批評、各子の状態を確認する。 | 親が確認した改稿成果物の絶対パスだけを批評役へ渡す。失敗なら批評と次ラウンドを停止する。 |

### 非ループ型の実行手順

`research`、`decide`、`debate`、`fanout`、`review`、`triage`、`spike` は、表の並列子を起動して
全 `state.json` が `ok` になった後で止まる。親が成果物を確認し、必要なら一部の子を再指示・
再実行し、統合役または judge の指示・優先順位・出力形式を決める。親だけが後段を起動できる。
後段の子には表で指定した成果物の絶対パスだけを渡し、本文を親の会話へ転記しない。
後段の `state.json` と成果物を親が確認し、`ok` のときだけ run を完了する。後段が `failed` または
`stopped`、または成果物を欠く場合は run を `failed` または `stopped` として記録して停止する。
その先へ進めない。

### `implement` と `refine` のラウンド

`implement` と `refine` は親が `max_rounds` を指定して管理する。各ラウンドは run の
`state.json` にラウンド番号、子の成果物の絶対パス、親の判断、状態を記録する。
親が指定しない場合、`implement` は `max_rounds` を 3、`refine` は `max_rounds` を 2 として開始する。

`refine` は改稿役を起動して成果物を確認し、批評役へ絶対パスを渡し、親が批評を確認して判断する。

1. `implement` では親が実装役を起動し、`refine` では親が改稿役を起動する。独立単位が複数なら
   並列に起動する。
2. 親が実装または改稿の `state.json` と成果物を確認する。失敗ならレビュー・批評を起動せず、
   `failed` または `stopped` を記録して停止する。
3. 親が許可したときだけ、実装成果物の絶対パスをレビュー役へ、または改稿成果物の絶対パスを
   批評役へ渡す。批評観点やレビュー役が複数なら並列に起動する。
4. 親がレビューまたは批評の成果物と `state.json` を確認し、完了、追加指示を伴う次ラウンド、
   停止のいずれかを決める。親だけが次ラウンドを起動できる。
5. `max_rounds` に到達しても完了判断が無ければ、成功扱いにせず run の最終状態を `unresolved`
   として記録して停止する。

## MAD に適さないとき

どのレシピの形にもはまらないなら MAD を使わず、従来どおり subagent を立てる。

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
