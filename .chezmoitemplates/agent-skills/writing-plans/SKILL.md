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

実装者はこのコードベースの前提知識をまったく持たず、判断の質も当てにできないものとして書く。各タスクで触るファイル、書くコード、テスト、確認すべき docs、テスト方法まで全部書く。全体を一口大のタスクに割って渡す。DRY、YAGNI、TDD、こまめなコミット。

実装者は開発者としては有能だが、このツールセットと問題領域はほぼ知らないものとする。良いテスト設計にも通じていないものとする。

**開始時に宣言する**: 「writing-plans を使って実装プランを作る」

**保存先**: `_cellfusion/plans/YYYY-MM-DD-<feature-name>.md`（プロジェクト側 CLAUDE.md の指定があればそちらを優先）

**書く前に** `~/.agents/skills/_shared/scripts/cellfusion-workdir` を実行する。`_cellfusion/` を作り、自己無視の `.gitignore` を置く。global の gitignore が無い環境（新しいマシン、他人の環境、CI）ではこれが唯一の無視の根拠になるので省略しない。

`_cellfusion/` は git 追跡外である。プランは `git clean -fdx` で消え、`git log` からは復旧できない。ブランチにも乗らないので worktree の中には現れない（後段のスキルへは絶対パスで渡す）。

## スコープ確認

spec が独立した複数のサブシステムに跨っているなら、本来 brainstorming で分割されているはずのもの。されていないなら、サブシステムごとにプランを分けることを提案する。各プランは単体で動作しテスト可能なソフトウェアを生む単位にする。

## ファイル構成

タスクを定義する前に、作成・変更するファイルと各ファイルの責務を洗い出す。分解の判断はここで固定される。

- 単位は明確な境界と定義済みインターフェースを持たせる。1 ファイル 1 責務
- 一度に context へ載る量のコードのほうが推論も編集も確実になる。大きく何でも入ったファイルより、小さく焦点の絞れたファイルを選ぶ
- 一緒に変わるファイルは一緒に置く。技術レイヤーではなく責務で割る
- 既存コードベースでは確立されたパターンに従う。コードベースが大きなファイルを使っているなら勝手に再構成しない。ただし変更対象のファイルが既に手に負えない大きさなら、分割をプランに含めてよい

この構成がタスク分解の土台になる。各タスクは単体で意味を持つ自己完結した変更を生む。

## タスクの粒度

タスクとは、それ自身のテストサイクルを持ち、新しいレビュアーの gate に掛ける価値がある最小単位。境界を引くときは、セットアップ・設定・スキャフォールド・ドキュメントの手順を、それを必要とする成果物のタスクに畳み込む。分けるのは、レビュアーが片方を承認しつつ隣を却下しうる場合だけ。各タスクは独立にテストできる成果物で終わる。

## ステップの粒度

**1 ステップ 1 動作（2-5 分）**:

- 「失敗するテストを書く」
- 「実行して失敗を確認する」
- 「テストを通す最小の実装を書く」
- 「テストを実行して通ることを確認する」
- 「コミットする」

## プラン文書のヘッダー

**すべてのプランはこのヘッダーで始める**:

```markdown
# [機能名] 実装プラン

> **実装エージェント向け**: このプランは自作スキルで実行する。
> subagent-driven-development（推奨）または executing-plans を使ってタスク単位で進める。
> ステップはチェックボックス（`- [ ]`）で追跡する。

**ゴール**: [何を作るかを 1 文で]

**アーキテクチャ**: [方針を 2-3 文で]

**技術スタック**: [主要な技術・ライブラリ]

## Global Constraints

[spec のプロジェクト全体に掛かる要件 — バージョン下限、依存の制限、
命名や文言の規則、プラットフォーム要件 — を 1 行ずつ、spec から
そのままの値で写す。すべてのタスクの要件はこの節を暗黙に含む。]

---
```

## タスクの構造

````markdown
### Task N: [コンポーネント名]

**Files:**
- Create: `exact/path/to/file.ts`
- Modify: `exact/path/to/existing.ts:123-145`
- Test: `tests/exact/path/to/test.ts`

**Depends on:** Task 2, Task 3

**Interfaces:**
- Consumes: [先行タスクから使うもの — 正確なシグネチャ]
- Produces: [後続タスクが依存するもの — 正確な関数名、引数と戻り値の型。
  実装者は自分のタスクしか見ないので、隣のタスクが使う名前と型はこのブロックでしか伝わらない]

- [ ] **Step 1: 失敗するテストを書く**

```typescript
test('specific behavior', () => {
  expect(fn(input)).toBe(expected);
});
```

- [ ] **Step 2: 実行して失敗を確認する**

実行: `npm test -- path/to/test.ts -t 'specific behavior'`
期待: FAIL（"fn is not defined"）

- [ ] **Step 3: 最小の実装を書く**

```typescript
export function fn(input: string): string {
  return expected;
}
```

- [ ] **Step 4: 実行して通ることを確認する**

実行: `npm test -- path/to/test.ts -t 'specific behavior'`
期待: PASS

- [ ] **Step 5: コミットする**

```bash
git add tests/path/test.ts src/path/file.ts
git commit -m "feat: add specific feature"
```
````

## タスクの依存

各タスクは、先に完了していなければ始められないタスクを `**Depends on:**` で宣言する。先行が無ければ `なし` と書く。

これは実行順の指定ではなく、**同時に走らせてよいタスクを見分けるため**の宣言である。依存の無いタスクどうしは別々の worktree で並行に実装される。

- **Interfaces の Consumes に他タスクの Produces が出てくるなら、そのタスクを Depends on に書く。** 例外なく
- **`Files:` が重なるタスクは並行にできない。** 同じファイルを触る 2 つのタスクは、どちらかがもう一方に依存する形にする
- 迷ったら依存を書く。並行にならないだけで、壊れることはない

`Depends on` を書かないタスクは、それより前の全タスク全部に依存するものとして扱われる（＝直列）。安全側には倒れるが、並行の余地は失われる。

波の計算と検証は `~/.agents/skills/subagent-driven-development/scripts/task-waves PLAN_FILE` が行う。循環、存在しないタスク参照、同じ波でのファイル重複を検出する。

## placeholder を書かない

各ステップには実装者が必要とする実際の内容が入っていること。以下は**プランの欠陥**であり、書いてはならない。

- 「TBD」「TODO」「あとで実装」「詳細は埋める」
- 「適切なエラー処理を追加」「バリデーションを入れる」「エッジケースを扱う」
- 「上記のテストを書く」（実際のテストコードなし）
- 「Task N と同様」（コードを再掲する。実装者はタスクを順番どおりに読むとは限らない）
- 何をするかだけ書いて、どうするかを書いていないステップ（コードのステップにはコードブロックが要る）
- どのタスクにも定義されていない型・関数・メソッドへの参照

## self-review

プランを書き終えたら、新しい目で spec と突き合わせる。subagent には投げず自分でやる。

1. **spec カバレッジ** — spec の各節・各要件をなぞり、それを実装するタスクを指させるか確認する。指せないものを列挙する
2. **placeholder 走査** — 上の「placeholder を書かない」に挙げたパターンを探して直す
3. **型の整合** — 後のタスクで使った型・シグネチャ・プロパティ名が、前のタスクで定義したものと一致するか。Task 3 で `clearLayers()`、Task 7 で `clearFullLayers()` になっていればバグ

4. **依存の整合** — `~/.agents/skills/subagent-driven-development/scripts/task-waves PLAN_FILE` を実行する。エラーが出たら直す。あわせて、Consumes に他タスクの Produces が出てくるのに Depends on に書いていないタスクが無いかを目視で確かめる

見つけたその場で直す。再レビューは不要。タスクの無い spec 要件が見つかったらタスクを足す。

{{ includeTemplate "agent-skills/_preview-tab.md" . }}

{{ includeTemplate "agent-skills/_approval-gate.md" (merge (dict "artifact" "plan" "nextLabel" "実装" "issue" false "worktree" true) .) }}

plan は issue にしない。実装エージェント（subagent-driven-development / executing-plans）が plan ファイルのパスを受け取って直接読む前提であり、ファイルが無いと実行方式が成り立たない。

{{ includeTemplate "agent-skills/_worktree-handoff.md" . }}

## 実装への引き継ぎ

承認されたら実行方式を決める。

- **既定は subagent-driven-development**。タスクごとに新しい subagent を立て、間にレビューを挟む
- **executing-plans** は subagent が使えない環境のときだけ。このセッションで直列に実行し、チェックポイントでレビューする

どちらでも、実装は隔離されたワークスペースで行う（using-git-worktrees）。

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「コードは実装者が考えればよい」 | 実装者はコードベースを知らない。プランのコードが唯一の仕様になる |
| 「Task N と同様、で伝わる」 | 実装者は自分のタスクしか読まない。参照は届かない |
| 「エラー処理は適切に、で十分」 | 「適切に」は何も指定していない。何を捕まえて何を返すか書く |
| 「タスクを細かく割ったほうが安全だ」 | 割りすぎるとレビュー単位が意味を失う。独立にテストできる成果物が最小単位 |
| 「self-review はレビュアーに任せる」 | 型の不整合と spec の抜けはプラン段階でしか安く直せない |
| 「プレビューは開かなくても伝わる」 | 開くのは gate の一部。読むかどうかをユーザーに選ばせない |
| 「自分が書いた内容だから読み直さなくてよい」 | プレビューは編集可で開く。手編集はファイルにしか残らない |
