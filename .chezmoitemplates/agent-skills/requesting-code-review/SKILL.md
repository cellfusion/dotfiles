---
name: requesting-code-review
description: >-
  作業の区切り、大きめの機能の実装後、merge 前にレビューを依頼するときに使う。
  レビュアー subagent に精密に組み立てた文脈だけを渡し、
  自分の context を調整のために温存する。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# コードレビューを依頼する

レビュアー subagent を dispatch して、問題が波及する前に捕まえる。レビュアーには**評価のために精密に組み立てた文脈**を渡す。あなたのセッション履歴は渡さない。

**中核**: 早く、こまめにレビューする。

## いつ依頼するか

**必須**:

- subagent-driven-development の各タスクの後（そちらのスキルが自動で行う）
- 大きめの機能を完了した後
- main へ merge する前

**任意だが有用**:

- 詰まったとき（視点を変える）
- リファクタリングの前（現状の基準を取る）
- 込み入ったバグを直した後

## 依頼のしかた

**1. diff をファイルにまとめる**

レビュアーの context に diff を 1 回の Read で載せる。SDD の workspace が使えるならそのスクリプトを使う。

```bash
BASE_SHA=$(git merge-base master HEAD)   # または対象範囲の起点
HEAD_SHA=$(git rev-parse HEAD)
```

SDD の外で単発に依頼する場合は、同じ内容を手で作る。

```bash
OUT=$(mktemp -t review).diff
{
  echo "# Review package: ${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Commits"; git log --oneline "${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Files changed"; git diff --stat "${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Diff"; git diff -U10 "${BASE_SHA}..${HEAD_SHA}"
} > "$OUT"
echo "$OUT"
```

**2. [dispatch-subagent: sdd-final-reviewer] する**

ロールプロンプトとレビュー基準はエージェント定義に入っている。dispatch プロンプトに渡すのは次の 4 つだけ。

- 何を実装したかの概要
- プランまたは要件のパス（無ければ要件を数行で）
- review package のパス
- 先送りされた指摘や park された指摘のリスト（あれば）

**3. フィードバックに対応する**

- Critical は直ちに直す
- Important は次へ進む前に直す
- Minor は記録して後で扱う
- レビュアーが誤っていれば技術的な根拠を添えて押し返す

受け取り方の作法は receiving-code-review を使う。

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「レビュアーを立てず自分で diff を見る」 | あなたは調整役である。diff をインラインで読むと、作業を進めるための context を焼く。レビュアー subagent を立てれば、diff と評価はそちらの context に載り、返ってくるのは指摘だけになる |
| 「レビュアーには自分のセッション履歴が要る」 | 精密に組み立てた文脈を渡す。履歴は渡さない。そうすればレビュアーは思考過程ではなく成果物を見る |
| 「単純だからレビューは省く」 | 単純な変更が壊すものは単純ではない |

## してはならないこと

- Critical を無視する
- Important を直さずに進む
- 妥当な技術的指摘と言い争う
- 特定の問題を指摘するなとレビュアーに指示する

**レビュアーが誤っている場合**:

- 技術的な根拠を添えて押し返す
- 動作を証明するコードやテストを示す
- 説明を求める
