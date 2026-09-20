---
name: multi-agent-development
description: >-
  複数の子エージェント、並列 task、worktree 隔離、または独立した review が必要な作業を
  Paseo MCP で実行する。単一 task の実装や通常の会話に自動適用しない。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD を必要な作業だけに使う

Multi-Agent Development（MAD）は、親エージェントが複数の子エージェントを管理するための実行 recipe である。MAD は依頼を理解する仕組みでも、複雑度を自動判定する仕組みでも、親の判断を置き換える仕組みでもない。

## MAD を使うか判断する

MAD を使うのは、次のいずれかを満たす場合だけである。

- 独立した task を並行して実装できる
- 調査、実装、レビューを別の child に分けることで品質または時間が改善する
- task ごとに worktree を分ける必要がある
- 長時間の作業を親の会話から分離する必要がある
- ユーザーが複数エージェントの利用を指定した

次の場合は MAD を使わない。

- 一つの task を親が直接実装できる
- 直列の小さな plan を `executing-plans` で処理できる
- child を作ることが調査や判断より重い
- review が必要でも、親が diff と検証結果を確認できる

MAD を使わないことは失敗ではない。MAD を使う価値が無いと判断したら、親が直接作業するか、`executing-plans` へ進む。

## 親の責務

親エージェントだけが次を決める。

- MAD を使うかどうか
- recipe、task、依存関係、並列数
- child に渡す role、scope、成果物、複雑度
- review の採用、再実行、モデルの引き上げ、停止
- ユーザーに判断を求めるかどうか

child の成功報告だけを根拠に採用しない。成果物、diff、テスト、scope、schema を確認してから採用する。

## 選べる recipe

| recipe | 使う場合 | 終了条件 |
|---|---|---|
| `research` | 観点の異なる調査を並行する | 全成果物を親が統合する |
| `fanout` | 独立した task を並行して処理する | 全 task の採用判断が終わる |
| `review` | 独立したレビュー観点が必要である | review package と verdict を検証する |
| `delivery` | spec、plan、実装、task review、final review が必要である | 全 phase の成果物と integration を確認する |
| `refine` | 既存成果物を限定 scope で改善する | scope 内の差分を検証する |

`spec` と `plan` は独立した recipe ではなく、必要な delivery の phase として扱う。単独の spec や plan を親が書いてもよい。

## 軽量な実行経路

MAD を使うと決めても、最初から full delivery にしない。次の順に必要なものだけを選ぶ。

1. **single child** — 一つの調査または一つの実装を child に任せる。親は成果物を確認する
2. **fanout** — 独立した child を並行して起動する。全 child の終了後に親が統合する
3. **delivery** — spec、plan、実装、review を分ける必要があるときだけ使う

single child が必要なだけなら、`multi-agent-development` の strict contract を使わず、Paseo の通常の child 起動経路を選べる。strict contract が必要な複数 child の run に入る場合だけ、末尾の共通契約を適用する。

## MAD run を開始する前

次を親が決めて記録する。

- run の目的と recipe
- 各 node の責務、入力、出力、許可された変更範囲
- 依存関係と並列にできる範囲
- 成功条件、停止条件、ユーザー判断が必要な条件
- 使う backend と、失敗時に別経路へ切り替えるかどうか

この判断を child に丸投げしない。Paseo MCP が使えず、strict MAD run を開始できない場合は、MAD を実行したことにせず、親が直接作業するかユーザーへ状況を伝える。

## plan を実装する strict MAD の準備

以下は、親が strict MAD で plan を実装すると決めた場合だけに適用する。MAD を採用する前や、plan の実装を含まない調査・review の gate にはしない。共通契約の実行pathを初期化し、task 抜粋に使う script を設定する。

```bash
MAD_TASK_BRIEF="$MAD_SCRIPTS/task-brief"
MAD_STATE_DIR="${MAD_STATE_DIR:-$HOME/.local/state/mad}"
MAD_WORKTREE="$MAD_SCRIPTS/mad-worktree"
MAD_PROGRESS="$MAD_SCRIPTS/mad-progress"
```

## delivery role map

delivery role は `implementer`、`task-reviewer`、`re-reviewer`、`final-reviewer` の 4 役である。plan-auditor は delivery role ではない。同じ prompt/schema 命名規則に従う read role として、実装前の one-shot gate を担当する。

## 共通手順

plan を実装する strict MAD では、次の順序を守る。

1. dependency gate と `--waves` を通し、wave 順序を確定する。
2. dependency gate の後、plan-auditor 用の provider/model discovery と `agent-config resolve` を共通契約に従って行う。最初の implementer create 前に実施し、解決した provider、model、modeId、thinkingOptionId、features を implementer 用には流用しない。
3. plan-auditor の launch を検証し、role prompt、schema、plan の absolute path を渡す plan-auditor の create request を作る。mode 0600 の `mcp-create.json` を再検証し、`"$MAD_VALIDATE" --prepare-create` で一回性 marker を取る。
4. marker を取れた場合だけ `plan-audit` node を create し、同一 run で一回だけ起動する。accepted response を縮約して保存し、wait 後に audit attempt の state、result、handoff を検証する。audit attempt が `ok` でなければ implementer を create しない。
5. findings が一件以上、または `decisionRequest` が non-null なら、全 findings と判断要求を一つの decision request に転記し、state と phase_state を `waiting_for_user` にして停止する。判断要求の `question`、`options`、`recommendation`、`confirmed` の4欄を保持する。同一 run で二度目の plan-audit を起動しない。
6. audit が `ok`、findings が空、`decisionRequest` が null のときだけ、最初の wave の implementer 用に discovery と resolve を行う。initial/fix ごとの実行情報を含む fresh な private `brief.md` を作り、その absolute path だけを `initialPrompt` に渡す。create・wait・成果物検証・wave ごとの取り込みは共通契約に従う。

## 実行中

strict contract を選んだ run では、次を守る。

1. run と attempt を一意に作り、既存成果物を上書きしない
2. role、prompt、schema、scope を child ごとに固定する
3. create、wait、stop、workspace 操作の回数を記録する
4. child の成果物を schema と scope で検証する
5. phase の境界で親が採用判断を記録する
6. review の scope を勝手に広げない
7. timeout、transport failure、未知の状態を成功として扱わない
8. run の上限に達したら、新しい child を追加せず停止する

詳細な request、state、artifact、review、workspace の契約は、実際に strict MAD run を開始するときだけ次の共通契約を読む。

{{ includeTemplate "agent-skills/_manual-orchestration.md" . }}
