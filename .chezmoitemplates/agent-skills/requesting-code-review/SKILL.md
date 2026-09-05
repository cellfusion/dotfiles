---
name: requesting-code-review
description: >-
  作業の区切り、実装後、merge 前のコードレビューを MAD の review recipe に委譲するときに使う。
---
{{ includeTemplate (printf "agent-skills/_runtime/%s.md" .tool) . }}

# MAD review の入口

親は本文を作らない。requirements、review package、対象成果物の絶対パスを MAD の `review` recipe に渡す。
子の観点別 `reviewer` が並列に評価し、`review-synthesizer` または `final-reviewer` が採用可能な指摘を
統合する。親は backend 選択、状態遷移、子の制御、ユーザー gate だけを担う。

## 実行

1. `PLAN_FILE`、`REQUIREMENTS_FILE`、`BASE`、`HEAD` を親の制御情報から決める。`PLAN_FILE` は既存の
   承認済み plan の絶対パス、`REQUIREMENTS_FILE` は plan が無い場合に使う既存 requirements の絶対パス、
   `BASE` は今回の変更を始めたコミット、`HEAD` はレビュー対象の現在コミットとする。`BASE` と `HEAD` は
   symbolic ref のまま渡さず、`git rev-parse --verify` で解決する。
2. `review-package` の実体を解決する。通常は
   `~/.agents/skills/subagent-driven-development/scripts/review-package` を使い、見つからない場合は
   この dotfiles checkout の `private_dot_agents/skills/subagent-driven-development/scripts/executable_review-package`
   を fallback にする。どちらも実行できない場合は package を作れないため MAD review を開始しない。
3. `cellfusion-workdir` を一度実行して `_cellfusion/` を自己無視させ、`OUTFILE` を
   `_cellfusion/reviews/review-<base7>..<head7>.diff` として親が作る。出力ディレクトリを先に作成し、
   次の既存 script の入力契約（`PLAN_FILE BASE HEAD OUTFILE`）をそのまま使う。

   ```bash
   REPO_ROOT="$(git rev-parse --show-toplevel)"
   PLAN_FILE="${PLAN_FILE:-}"
   REQUIREMENTS_FILE="${REQUIREMENTS_FILE:-}"
   if [ ! -f "$PLAN_FILE" ]; then
     PLAN_FILE="$REQUIREMENTS_FILE"
   fi
   case "$PLAN_FILE" in
     /*) ;;
     *)
       echo "review package の入力 file を確認できないため MAD review を開始しない" >&2
       exit 2
       ;;
   esac
   if [ ! -f "$PLAN_FILE" ]; then
     echo "review package の入力 file を確認できないため MAD review を開始しない" >&2
     exit 2
   fi
   REVIEW_PACKAGE="$HOME/.agents/skills/subagent-driven-development/scripts/review-package"
   if [ ! -f "$REVIEW_PACKAGE" ]; then
     REVIEW_PACKAGE="$REPO_ROOT/private_dot_agents/skills/subagent-driven-development/scripts/executable_review-package"
   fi
   CELLFUSION_WORKDIR="$HOME/.agents/skills/_shared/scripts/cellfusion-workdir"
   if [ ! -f "$CELLFUSION_WORKDIR" ]; then
     CELLFUSION_WORKDIR="$REPO_ROOT/private_dot_agents/skills/_shared/scripts/executable_cellfusion-workdir"
   fi
   if [ ! -f "$REVIEW_PACKAGE" ] || [ ! -f "$CELLFUSION_WORKDIR" ]; then
     echo "review package の script を解決できないため MAD review を開始しない" >&2
     exit 2
   fi
   bash "$CELLFUSION_WORKDIR" >/dev/null
   BASE="$(git rev-parse --verify "$BASE")"
   HEAD="$(git rev-parse --verify "$HEAD")"
   OUTFILE="$REPO_ROOT/_cellfusion/reviews/review-${BASE:0:7}..${HEAD:0:7}.diff"
   mkdir -p "$(dirname "$OUTFILE")"
   bash "$REVIEW_PACKAGE" "$PLAN_FILE" "$BASE" "$HEAD" "$OUTFILE"
   if ! test -s "$OUTFILE" || ! grep -Fq "# Review package: ${BASE}..${HEAD}" "$OUTFILE"; then
     echo "review package の生成結果を確認できないため MAD review を開始しない" >&2
     exit 2
   fi
   ```

   `PLAN_FILE` が無い場合は inline text を渡さず、`requirements` の絶対パスである
   `REQUIREMENTS_FILE` を `PLAN_FILE` へ代入して同じ `review-package` 呼び出しに使う。どちらも
   存在しない、絶対パスでない、`BASE` / `HEAD` を解決できない、または script が失敗した場合は
   [ask-user] で必要なファイルまたは ref を求め、package を作れない場合は MAD review を開始しない。
4. review package を正規 `_cellfusion/reviews/` または SDD ledger に作り、その絶対パスを入力にする。
   親は diff や要件を会話へ転記してレビュー本文を作らない。
5. MAD の `review` を開始する。各子は findings と統合 review の絶対パスを `handoff.json` に残す。
6. 親は各 attempt の state と統合前 handoff を確認する。失敗 review、成果物欠落、重要な要件変更が
   あれば統合を完了にせず、再指示・再実行・停止を裁定する。
7. 要件変更または remediation の優先順位にユーザー判断が必要な場合だけ [ask-user] で relay し、
   `waiting_for_user` に記録する。
8. 採用 attempt の最終 review 成果物だけを後段の MAD `implement` または `delivery` phase へ絶対パスで
   handoff する。

Critical または Important を自分で直さない。修正が必要なら該当成果物を MAD の `implement` recipe へ
渡し、子の TDD と再 review を通す。
