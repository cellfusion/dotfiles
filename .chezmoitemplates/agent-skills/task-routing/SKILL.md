---
name: task-routing
description: >-
  依頼の実行経路、作業クラス、実装 role を選ぶ。明確で局所的な変更には使わず、direct、single、delivery の判断が必要な場合だけ使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# 依頼を実行経路へ振り分ける

task-routing は、ユーザーの依頼を実装用の task packet に整理する入口である。実装そのもの、設計の承認、MAD の strict contract は担当しない。明確で局所的な変更はこの skill を使わず、親が直接実装するか、軽量な `implementer` child を起動する。

## 出力する task packet

次の有限値を持つ packet を親の判断材料にする。自由な model/provider の選択は packet に入れない。

```json
{
  "route": "direct|single|delivery",
  "workClass": "mechanical|routine|integration|architectural",
  "role": "implementer|architectural-implementer",
  "complexity": "simple|routine|complex|critical",
  "goal": "...",
  "writeScope": ["..."],
  "acceptanceCriteria": ["..."],
  "verification": ["..."],
  "needsBrainstorming": false,
  "needsUserDecision": false,
  "confidence": "high|medium|low",
  "reason": "..."
}
```

`writeScope`、`acceptanceCriteria`、`verification` が不明なまま `confidence: high` にしない。推測で結果が変わる場合は `needsUserDecision` を `true` にする。

## route の判断

### direct

親が直接実装する。

- 既存の一つの処理を変更する
- ファイルが1〜2個である
- 依頼文から挙動が確定している
- 外部操作、公開契約、設計選択がない

### single

一つの child に実装を委譲する。full MAD、plan-auditor、task review loop は起動しない。

- 変更は明確だが、親の context から分離する価値がある
- 実装と検証を別の child に任せたい
- task は一つで、並列性がない

child には task packet、対象ファイル、acceptance criteria、verification、必要な制約だけを渡す。過去の会話全文や無関係な plan を渡さない。親は child の commit、diff、テスト、scope を確認する。

### delivery

複数段階の設計・実装・review が必要な場合だけ `writing-plans` と `multi-agent-development` へ進む。

- 独立 task を並行できる
- worktree 隔離が必要である
- 複数層の統合や公開契約の変更がある
- task review と final review が必要である

## workClass の判断

### mechanical

既存の実装パターンをそのまま使う。文字列置換、path の変更、形が決まった小さな修正が該当する。新しい抽象化や設計変更を行わず、疑問が出たら停止または escalation する。

### routine

既存の設計に沿って数ファイルを変更する。実装者は対象コード、既存テスト、acceptance criteria を確認して実装する。

### integration

複数層、複数パッケージ、複数の呼び出し元を接続する。契約、データの流れ、エラー処理、統合テストを確認する。task review を省略しない。

### architectural

新しいサブシステム、公開契約、schema、認証、migration、複数の妥当な設計案がある変更に使う。実装者に設計を発明させない。`spec-author`、`plan-author`、`plan-auditor` の後に `architectural-implementer` または強い `implementer` を起動する。

## role の判断

同じ artifact contract、権限、停止条件で実装できるなら `implementer` に workClass overlay を渡す。次が変わる場合だけ別 role を選ぶ。

- 設計判断を許すか
- 書き込み範囲や権限が違うか
- 成果物 schema が違うか
- review 経路や停止条件が違うか

model、effort、attempt の level は role ではなく `attemptPolicy` で決める。`escalation-judge` を使う場合も、judge は level と workClass を提案するだけで、provider/model を自由に決めない。

## user decision と brainstorming

次の場合だけユーザーへ確認する。

- 挙動の選択が依頼文から決まらない
- scope、公開契約、破壊的操作、外部 side effect が変わる
- architectural な設計案の選択が残る
- confidence が低く、安全な仮定を置けない

`needsBrainstorming` が `true` の場合は、目的・制約・成功条件を整理してから brainstorming を使う。明確な local change では brainstorming を起動しない。

## 終了条件

- `direct`: 親が実装し、適切な検証を行う
- `single`: implementer child を一つ起動し、親が成果物を採用する
- `delivery`: spec、plan、audit、MAD delivery へ引き渡す
- `needsUserDecision`: decision request を作り、実装を開始しない

route の判定だけで無限に質問しない。目的、scope、acceptance criteria が揃えば次の経路へ進む。
