---
name: requesting-code-review
description: >-
  作業の区切り、大きめの機能の実装後、merge 前にレビューを依頼するときに使う。
  レビューする子には評価のために精密に組み立てた文脈だけを渡し、
  自分の context を調整のために温存する。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# コードレビューを依頼する

レビュアー subagent を dispatch するか、SDD の外なら MAD の `review` recipe を使って、問題が
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

`~/.agents/skills/subagent-driven-development/scripts/review-package PLAN_FILE BASE HEAD OUTFILE`
が使えるならそれを使う。使えない環境では下の手順で同じ形の package を作る。

```bash
BASE_SHA=$(git merge-base master HEAD)   # または対象範囲の起点
HEAD_SHA=$(git rev-parse HEAD)
```

SDD の外で単発に依頼する場合は、`agent-docs-dir reviews` が返すディレクトリに正本を作る。`/tmp` を使わないのは、レビューが終わったあとも正本を読み返せる場所に残すためである。

```bash
REVIEWS="$(~/.agents/skills/_shared/scripts/agent-docs-dir reviews)"
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

SDD の中では `sdd-final-reviewer` を [dispatch-subagent] する。SDD の外で単発に依頼する場合は
MAD の `review` recipe を使う。呼び方は `multi-agent-development` スキルが持つ。

どちらの経路でも、渡すのは次の 4 つだけである。セッション履歴を渡さない。

- 何を実装したかの概要
- プランまたは要件の絶対パス（無ければ要件を数行で）
- review package の絶対パス
- 先送りされた指摘や park された指摘のリスト（あれば）

MAD の `review` は観点別の `reviewer` を並列に起動し、`review-synthesizer` が採用可能な指摘へ
統合する。統合結果は critical と important の finding が 1 件も無いときだけ `approved` になる。

review package も plan もリポジトリの作業ツリーの外にある。子は呼び出し元の作業ディレクトリの
外を読めない engine 設定でも動く必要があるので、渡す前に `<repo-root>/.agent-review/` の下の
一意なディレクトリへ複製し、複製先の絶対パスを渡す。

```bash
# 要件ファイルの正本。plan なら agent-docs-dir plans の下にある
REQ_SRC="$(~/.agents/skills/_shared/scripts/agent-docs-dir plans)/PLAN.md"

# 子は cwd の外を読めないので、リポジトリ内へ複製してから渡す。
# root は従来の内容を残し、実行ごとの一意なサブディレクトリだけを消す。
STAGE_ROOT="$(git rev-parse --show-toplevel)/.agent-review"
mkdir -p "$STAGE_ROOT"
if [ ! -e "$STAGE_ROOT/.gitignore" ]; then
  printf '*\n' > "$STAGE_ROOT/.gitignore"
fi
STAGE="$(mktemp -d "$STAGE_ROOT/run.XXXXXX")"
cleanup() { rm -rf -- "$STAGE"; }
trap cleanup EXIT
# trap は成功しても失敗しても、一意な複製先だけを消す。
cp "$OUT" "$STAGE/"
cp "$REQ_SRC" "$STAGE/"
STAGED_REVIEW="$STAGE/$(basename "$OUT")"
STAGED_REQ="$STAGE/$(basename "$REQ_SRC")"
```

要件をファイルではなく文字列で渡すときは、`STAGED_REQ` の代わりに概要と要件を数行にまとめた
文字列を子へ渡す。複製が要るのは review package だけになる。

`.agent-review/` に置く `.gitignore` は自己無視である。global の gitignore が無い環境でも複製が
コミットに混ざらないようにする。削除できずに残っても、自己無視が効くので `git status` には
出ない。

**3. フィードバックに対応する**

- Critical は直ちに直す。直すのは子である。親は指摘と review package の絶対パスを MAD の
  `implement` recipe へ渡す
- Important は次へ進む前に直す。渡すものと経路は Critical と同じにする
- Minor は記録して後で扱う
- レビュアーが誤っていれば技術的な根拠を添えて押し返す

**親は Critical と Important を自分で直さない。** 親が書いた修正は独立したレビュアーの判定を
受けない。修正の diff とテスト出力も親の会話に残り、以降のターンで毎回読み直される。

受け取り方の作法は receiving-code-review を使う。

## よくある言い訳

| 言い訳 | 実際 |
|---|---|
| 「レビュアーを立てず自分で diff を見る」 | あなたは調整役である。diff をインラインで読むと、その diff は以降のターンで毎回読み直され、調整に使える context が減る。レビュアー subagent を立てれば、diff と評価はそちらの context に載り、返ってくるのは指摘だけになる |
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
