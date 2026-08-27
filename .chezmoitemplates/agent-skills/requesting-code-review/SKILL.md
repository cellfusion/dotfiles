---
name: requesting-code-review
description: >-
  作業の区切り、大きめの機能の実装後、merge 前にレビューを依頼するときに使う。
  レビュアー subagent に精密に組み立てた文脈だけを渡し、
  自分の context を調整のために温存する。
  SDD の外で単発に依頼する場合はレビュアー subagent の代わりに braid の
  review レシピを呼ぶ。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# コードレビューを依頼する

レビュアー subagent を dispatch するか、SDD の外なら braid の review レシピを呼んで、問題が
波及する前に捕まえる。どちらの経路でも、レビュー側には**評価のために精密に組み立てた文脈**を
渡す。あなたのセッション履歴は渡さない。

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

レビュアーの context に diff を 1 回の Read で載せる。SDD の中では従来経路を維持し、SDD の
workspace のスクリプトを使う。

```bash
BASE_SHA=$(git merge-base master HEAD)   # または対象範囲の起点
HEAD_SHA=$(git rev-parse HEAD)
```

SDD の外で単発に依頼する場合は、リポジトリ内の `_cellfusion/reviews/` に作る。`/tmp` を使わない
のは、read 役が現在の作業ディレクトリの外を読めない engine 設定でも同じ入力を読めるようにする
ためである。`_cellfusion/` が無ければ
`~/.agents/skills/_shared/scripts/cellfusion-workdir` が作る。

```bash
REVIEWS="$(~/.agents/skills/_shared/scripts/cellfusion-workdir)/reviews"
mkdir -p "$REVIEWS"
OUT="$REVIEWS/review-${BASE_SHA:0:7}..${HEAD_SHA:0:7}.diff"
{
  echo "# Review package: ${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Commits"; git log --oneline "${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Files changed"; git diff --stat "${BASE_SHA}..${HEAD_SHA}"
  echo; echo "## Diff"; git diff -U10 "${BASE_SHA}..${HEAD_SHA}"
} > "$OUT"
echo "$OUT"
```

**2. レビューを依頼する**

SDD の中では従来経路を維持する。[dispatch-subagent: sdd-final-reviewer] し、dispatch プロンプト
には次の 4 つだけを渡す。

- 何を実装したかの概要
- プランまたは要件のパス（無ければ要件を数行で）
- review package のパス
- 先送りされた指摘や park された指摘のリスト（あれば）

SDD の外で単発に依頼する場合は `braid run review` を呼ぶ。上の 4 項目をレシピの 2 引数へ移す。
必ずリポジトリルートで実行する。「braid の呼び方」の「引数」節が定めるとおり、`--arg` で渡す
パスは実行時の cwd の下になければ read 役が読めない。`requirements` に渡す要件ファイルが
リポジトリ外にあるなら、package と同じ `$REVIEWS` へ複製してからそのパスを渡す。

| 渡すもの | 移す先 |
|---|---|
| review package のパス | `review_file` |
| プランまたは要件のパス | `requirements` |
| 何を実装したかの概要 | 要件のパスが無い場合、概要と要件を数行にまとめた文字列を `requirements` に渡す |
| 先送り・park された指摘のリスト | `requirements` に含める |

```bash
REQ=<パスまたは要件の文字列>
braid run review --arg requirements="$REQ" --arg review_file="$OUT"
```

呼び方は下の「braid の呼び方」に従う。dry-run を先に通す。

`review` レシピは 3 つの `reviewer` を並列に走らせ、後段の `reviewer` が統合して `PASS` /
`FAIL` と findings を返す。critical と important が 0 件のときだけ `PASS` になる。

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

{{ includeTemplate "agent-skills/_braid-invocation.md" . }}
