---
name: writing-plans
description: >-
  spec や要件が固まった多段階の作業を、コードに触る前に実装プランへ落とすときに使う。
  architectural な設計が固まった後など、複数段階の実装に plan が必要な場合だけ起動する。
  プランは agent-docs-dir plans が返す場所に書き、実行方法に応じて後段へ引き継ぐ。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 実装プランを書く

## 概要

plan は、親が直接書いても、必要に応じて child に書かせてもよい。小さな plan では親が対象コードを読んで task、依存関係、検証方法を決める。長時間の調査、独立した task 分解、別の観点による確認が必要な場合だけ `plan-author` や review child を使う。

親は plan の目的、前提、採用判断に責任を持つ。child の利用は品質を上げる手段であり、plan 作成の前提ではない。

plan がどうあるべきかの基準は、`_criteria-plan.md` と必要な validator が持つ。

**保存先**: `~/.agents/skills/_shared/scripts/agent-docs-dir plans` が返すディレクトリの
`YYYY-MM-DD-<feature-name>.md`（プロジェクト側 CLAUDE.md の指定があればそちらを優先）

**始める前に** `~/.agents/skills/_shared/scripts/agent-docs-dir plans` を実行する。保存先を作って
絶対パスを 1 行で返す。保存先は `~/docs/<owner>/<repo>/plans/` である。

保存先はリポジトリの作業ツリーの外にある。本体チェックアウトから呼んでも worktree から呼んでも
同じ絶対パスになるので、後段のスキルへは絶対パスで渡す。

## スコープ確認

spec が独立した複数のサブシステムに跨っているなら、本来 brainstorming で分割されているはずのもの。されていないなら、サブシステムごとにプランを分けることを提案する。各プランは単体で動作しテスト可能なソフトウェアを生む単位にする。

## plan を書く

`~/.agents/skills/_shared/scripts/agent-docs-dir plans` を実行して保存先を決める。親が plan を書く場合も、child に書かせる場合も、plan の絶対 path を後段へ渡す。

child に書かせる場合は、目的、承認済み spec の絶対 path、既知の制約、plan の保存先だけを渡す。child が質問した場合は、親が内容を確認してからユーザーへ転送する。親が判断を隠して child に決めさせない。

## plan を確認する

親は plan を読み、task の依存関係、変更ファイル、検証方法、実装可能性を確認する。plan が大きい、独立 task が多い、または別の確認が必要な場合だけ `plan-author` や `reviewer` を追加する。

plan の task 番号、依存関係、同一 wave のファイル衝突は `paseo-plan-dependency-validate` などの既存 validator で確認する。validator の指摘を採用するかは親が決める。重大な曖昧さや実装を妨げる欠陥が残る場合だけ、ユーザーへ確認してから plan を直す。

重大な曖昧さや実装を妨げる指摘が残った場合、親は次のいずれかを選ぶ。

- 指摘を根拠付きで退ける
- plan の未解決事項に残して実装時の制約にする
- ユーザーへ確認して plan を修正する

指摘を黙って捨てない。

{{ includeTemplate "agent-skills/_preview-tab.md" . }}

{{ includeTemplate "agent-skills/_approval-gate.md" (merge (dict "artifact" "plan" "nextLabel" "実装" "issue" false "worktree" true) .) }}

plan は issue にしない。実装エージェント（multi-agent-development / executing-plans）が plan ファイルのパスを受け取って直接読む前提であり、ファイルが無いと実行方式が成り立たない。

{{ includeTemplate "agent-skills/_worktree-handoff.md" . }}

## 実装への引き継ぎ

承認されたら実行方式を決める。判断の基準は subagent が使えるかどうかではなく、plan の規模である。

- **並列にできるタスクを持つ plan、または worktree の隔離が要る plan** は
  multi-agent-development に渡す。task ごとに Paseo の子を立て、間に review recipe を挟む
- **実装が小さく、MAD を使わなくてよい plan** は executing-plans に渡す。このセッションで直列に
  実行し、タスクの区切りでレビューする

どちらに渡すか迷ったら、task の依存関係、変更ファイルの衝突、レビューの必要性で決める。並列性や隔離が不要なら `executing-plans` を使う。

`multi-agent-development` を選んだ場合だけ、MAD の strict contract と worktree の隔離を使う。

## 注意

- plan の内容を親が判断できる規模なら、child の review を追加しない
- task の依存関係とファイル衝突は、可能なら既存 validator で確認する
- plan の内容や実行方法でユーザーの選択が必要な場合だけ、選択肢と影響を示して確認する
- plan を読み直し、手編集や作業環境の差分を取り込んでから後段へ渡す
