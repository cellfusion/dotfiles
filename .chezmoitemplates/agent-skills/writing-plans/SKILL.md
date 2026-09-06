---
name: writing-plans
description: >-
  spec や要件が固まった多段階の作業を、コードに触る前に実装プランへ落とすときに使う。
  brainstorming の次段として起動する。プランは _cellfusion/plans/ に書き、
  承認後に subagent-driven-development へ引き継ぐ。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 実装プランを書く

## 概要

plan を書くのは子である。親は承認済み spec の絶対パスを渡し、結果を待つ。親は plan の本文、
タスク分解、依存関係を自分で作らない。

plan がどうあるべきかの基準は、`plan-author` と `reviewer` の role プロンプトが持つ。実装者は
このコードベースの前提知識を持たず、判断の質も当てにできないものとして書かれる。

**開始時に宣言する**: 「writing-plans を使って実装プランを作る」

**保存先**: `_cellfusion/plans/YYYY-MM-DD-<feature-name>.md`（プロジェクト側 CLAUDE.md の指定が
あればそちらを優先）

**始める前に** `~/.agents/skills/_shared/scripts/cellfusion-workdir` を実行する。`_cellfusion/` を
作り、自己無視の `.gitignore` を置く。global の gitignore が無い環境（新しいマシン、他人の環境、
CI）ではこれが唯一の無視の根拠になるので省略しない。

`_cellfusion/` は git 追跡外である。プランは `git clean -fdx` で消え、`git log` からは復旧
できない。ブランチにも乗らないので worktree の中には現れない（後段のスキルへは絶対パスで渡す）。

## スコープ確認

spec が独立した複数のサブシステムに跨っているなら、本来 brainstorming で分割されているはずのもの。されていないなら、サブシステムごとにプランを分けることを提案する。各プランは単体で動作しテスト可能なソフトウェアを生む単位にする。

## plan を書かせる

MAD の `plan` recipe で `plan-author` を呼ぶ。呼び方は `multi-agent-development` スキルが持つ。

子へ渡すのは、承認済み spec の絶対パス、plan の書き出し先、既存 ledger の絶対パス（あれば）で
ある。spec の本文を会話へ転記しない。

子が `decisionRequestPath` を返したら、親が [ask-user] でユーザーへ渡し、回答を `decision.md` に
書いて子を再開する。親が子に代わって判断しない。

## plan を判定する

判定するのも子である。`reviewer` が plan を読み、`PASS` か `FAIL` と findings を返す。判定の基準は
`reviewer` の role プロンプトが持つ。親は plan の本文を読んで良し悪しを決めない。

`FAIL` が返ったら、指摘の絶対パスを添えて `plan-author` を再度起動する。1 回の再起動と 1 回の
再判定で 1 ラウンドとする。**上限は 2 ラウンドである。**

上限に達しても `PASS` にならない場合、親が残った指摘を 1 件ずつ裁定する。裁定は 3 つに振り分ける。

- **指摘が誤っている、または議論の余地がある** — 理由を添えて退ける。理由を run state の
  `parent_decision` に記録する
- **本物だが、実装を妨げない** — plan にそのまま残し、実装スキルへ申し送る
- **本物で、かつ実装を妨げる** — 止める。指摘と、衝突している plan の記述を並べてユーザーに
  報告する

**裁定は上限に達したときだけ行う。** 黙って捨てることは禁止する。

{{ includeTemplate "agent-skills/_preview-tab.md" . }}

{{ includeTemplate "agent-skills/_approval-gate.md" (merge (dict "artifact" "plan" "nextLabel" "実装" "issue" false "worktree" true) .) }}

plan は issue にしない。実装エージェント（subagent-driven-development / executing-plans）が plan ファイルのパスを受け取って直接読む前提であり、ファイルが無いと実行方式が成り立たない。

{{ includeTemplate "agent-skills/_worktree-handoff.md" . }}

## 実装への引き継ぎ

承認されたら実行方式を決める。判断の基準は subagent が使えるかどうかではなく、plan の規模である。

- **並列にできるタスクを持つ plan、または worktree の隔離が要る plan** は
  subagent-driven-development に渡す。タスクごとに子を立て、間にレビューを挟む
- **実装が小さく、MAD を使わなくてよい plan** は executing-plans に渡す。このセッションで直列に
  実行し、タスクの区切りでレビューする

どちらに渡すか迷ったら subagent-driven-development にする。並列にならないだけで、壊れることは
ない。

subagent-driven-development を選んだ場合、実装は隔離されたワークスペースで行う
（using-git-worktrees）。

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「判定はレビュアーに任せて上限前に打ち切る」 | 裁定は上限に達したときだけ行う。早く終わらせるための裁定は先回りである |
| 「プレビューは開かなくても伝わる」 | 開くのは gate の一部。読むかどうかをユーザーに選ばせない |
| 「自分が書いた内容だから読み直さなくてよい」 | プレビューは編集可で開く。手編集はファイルにしか残らない |
