---
name: executing-plans
description: >-
  承認済み実装 plan を実行するとき、MAD の implement recipe に委譲する入口。親が直列実装する代替経路は持たない。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD implement の入口

親は本文を作らない。`executing-plans` は親が plan を直列に実装する経路ではなく、MAD の `implement`
recipe を使う互換入口である。承認済み plan、spec、既存 ledger の絶対パスだけを子へ渡す。

`implement` recipe の手順は `multi-agent-development` スキルが持つ。run ディレクトリの作り方、
backend の選び方、子の起動、state と handoff の契約はそこに書いてある。
MAD の `implement` を開始する前に `~/.agents/skills/multi-agent-development/SKILL.md` を読み込む。

1. MAD の `implement` を開始する。Paseo MCP が利用できなければ native subagent を選ぶが、開始後に
   backend を自動変更しない。
2. worktree を作るのは親である。子は親が渡した worktree の中で task graph、実装、TDD、review、
   fix loop を行い、成果物の絶対パスを `handoff.json` に残す。親は task 本文、実装、review 本文を
   作らない。
3. 親は state、採用 attempt、retry 上限、失敗・競合・例外だけを制御する。ユーザー判断が必要な場合だけ
   [ask-user] で relay し、`waiting_for_user` にする。
4. final review と検証記録が揃った採用 attempt だけを後段へ handoff する。未解決なら `unresolved` として
   停止する。

backend がどちらも使えない場合は、親が実装を代行せず blocked として必要な環境を報告する。
