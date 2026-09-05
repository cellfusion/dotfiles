---
name: subagent-driven-development
description: >-
  承認済み実装 plan を MAD の implement recipe で子エージェントに実装・レビューさせるときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD implement の入口

親は本文を作らない。承認済み plan、spec、既存 SDD ledger の絶対パスを MAD の `implement` recipe に渡す。
子の `task-graph-analyzer`、`implementer`、`task-reviewer`、`re-reviewer`、`final-reviewer` が task graph、
実装、review、fix loop、最終 review を担う。独立 task は子として並列起動する。

`implement` recipe の手順は `multi-agent-development` スキルが持つ。run ディレクトリの作り方、
backend の選び方、子の起動、state と handoff の契約はそこに書いてある。
MAD の `implement` を開始する前に `~/.agents/skills/multi-agent-development/SKILL.md` を読み込む。

## 子の工程規約

- 実装子は `test-driven-development` を使い、RED を確認してから最小実装で GREEN にする。
- 不具合・失敗を扱う子は `systematic-debugging` で根本原因を特定してから修正する。
- 並列 task の隔離は `using-git-worktrees` の規約に従う。worktree を作るのは親である。子は親が渡した
  worktree の中で実装し、自分では worktree を作らない。取り込みと後片付けも親が行う。親は実装や review の
  本文を代行しない。
- 子は brief、report、review package、検証記録を正規 `_cellfusion/sdd/` に残し、run 側の
  `handoff.json` には絶対パスだけを記録する。

## 親の制御

1. MAD の `implement` を開始し、backend は共通 selector で一度だけ選ぶ。
2. 親は state、採用 attempt、`handoff.json`、wave、retry 上限、失敗・競合・例外だけを確認・裁定する。
   task 本文、実装、review 本文を作らない。
3. plan によりユーザー判断が必要な場合だけ [ask-user] で relay し、run を `waiting_for_user` に記録する。
4. `max_rounds` 到達時は `unresolved` として停止する。採用 attempt の検証記録と final review が揃わない
   run を `ok` にしない。

完了後は final review の handoff を MAD の `review` または `delivery` phase へ絶対パスで渡す。
