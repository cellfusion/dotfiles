#!/usr/bin/env bash
# レシピが正しい数のノードを正しい役割で組み立てることを、--dry-run で検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/scripts" "$FIXTURE/defs" "$FIXTURE/repo" "$FIXTURE/bin" "$FIXTURE/paseo"
cp "$SRC/scripts/executable_mad-run" "$FIXTURE/scripts/mad-run"
cp "$SRC/scripts/executable_mad-route" "$FIXTURE/scripts/mad-route"
cp "$SRC/scripts/executable_mad-agent" "$FIXTURE/scripts/mad-agent"
cp "$SRC/scripts/mad-lib.sh" "$FIXTURE/scripts/mad-lib.sh"
chmod +x "$FIXTURE/scripts/mad-run" "$FIXTURE/scripts/mad-route" "$FIXTURE/scripts/mad-agent"

for f in manifests paseo-providers paseo-routing paseo-project-routing; do
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/$f.json\" . }}" > "$FIXTURE/defs/$f.json"
done

# 偽の paseo。provider の一覧のほか、run では title からノード名を読んで固定の JSON を返す。
# FAKE_FAIL_MARK を含むプロンプトのときだけ非ゼロで終わる。
cat > "$FIXTURE/bin/paseo" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "provider ls") cat "$FAKE_DIR/providers.json"; exit 0 ;;
  "provider models") cat "$FAKE_DIR/models.json"; exit 0 ;;
  "workspace create")
    printf '{"workspaceId":"wks_fake","project":"p","name":"n","isolation":"worktree","cwd":"%s/wt"}\n' \
      "$FAKE_DIR"
    exit 0 ;;
esac
[ "$1" = "run" ] || exit 1
prompt="${!#}"
if [ -n "${FAKE_FAIL_MARK:-}" ]; then
  case "$prompt" in
    *"$FAKE_FAIL_MARK"*) printf 'boom\n' >&2; exit 3 ;;
  esac
fi
title=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    *) shift ;;
  esac
done
node="${title##*/}"
case "$node" in
  review-*|final)
    printf '{ "status": "%s", "findings": [], "strengths": null }\n' \
      "${FAKE_REVIEW_STATUS-PASS}" ;;
  verdict)
    printf '{ "winner": "spike-1", "scores": [], "reason": "理由" }\n' ;;
  critique-*)
    printf '{ "status": "%s", "findings": [], "strengths": null }\n' \
      "${FAKE_REVIEW_STATUS-PASS}" ;;
  revise-*)
    printf '{ "files": ["draft.md"], "changes": ["直した"], "skipped": null }\n' ;;
  implement-*|spike-*)
    printf '{ "baseHead": "abc123", "changedFiles": ["a.txt"], "summary": "出力 %s" }\n' \
      "$node" ;;
  *)
    printf '{ "summary": "出力 %s" }\n' "$node" ;;
esac
FAKE
chmod +x "$FIXTURE/bin/paseo"

# 本実行は役割ごとの system prompt とスキーマを読む。
mkdir -p "$FIXTURE/defs/prompts" "$FIXTURE/defs/schemas"
for role in researcher synthesizer judge reviewer implementer writer; do
  printf 'あなたは %s である。\n' "$role" > "$FIXTURE/defs/prompts/$role.md"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$role.json\" . }}" > "$FIXTURE/defs/schemas/$role.json"
done

cat > "$FIXTURE/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$FIXTURE/repo" ;;
  "remote get-url origin") printf '\n' ;;
  "branch --show-current") printf '%s\n' "\${FAKE_BRANCH-main}" ;;
  *diff*)
    case "\${FAKE_DIFF_MODE-lines}" in
      empty) exit 0 ;;
      fail) printf 'fatal: bad revision\n' >&2; exit 128 ;;
      *) printf '+変更した行\n' ;;
    esac ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git"

cat > "$FIXTURE/paseo/providers.json" <<'JSON'
[ { "provider": "claude", "status": "available", "enabled": "Enabled" },
  { "provider": "codex", "status": "available", "enabled": "Enabled" } ]
JSON
cat > "$FIXTURE/paseo/models.json" <<'JSON'
[ { "id": "gpt-5.6-luna", "thinkingOptionIds": ["low","medium","high","max"] },
  { "id": "gpt-5.6-terra", "thinkingOptionIds": ["low","medium","high","max"] },
  { "id": "gpt-5.6-sol", "thinkingOptionIds": ["low","medium","high","max"] },
  { "id": "claude-sonnet-5", "thinkingOptionIds": ["low","medium","high","max"] },
  { "id": "claude-opus-5", "thinkingOptionIds": ["low","medium","high","max"] } ]
JSON

dry() {
  MAD_RECIPES_DIR="$SRC/recipes" \
  MAD_DEFS_DIR="$FIXTURE/defs" \
  MAD_PASEO_BIN="$FIXTURE/bin/paseo" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  FAKE_DIR="$FIXTURE/paseo" \
  bash "$FIXTURE/scripts/mad-run" "$@" --dry-run 2>/dev/null
}

# research: 観点 3 つ + 統合 1 つ。
out="$(dry research --arg topic=対象)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=research-')" "3" "research: 観点の数だけノードを作る"
assert_contains "$out" "node=research-1 role=researcher" "research: 観点は researcher"
assert_contains "$out" "node=synthesis role=synthesizer" "research: 統合は synthesizer"

out="$(dry research --arg topic=対象 --arg 'perspectives=["a","b"]')"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=research-')" "2" "research: 観点を差し替えられる"

out="$(dry research --arg topic=対象 --arg researcher_role=reviewer)"
assert_contains "$out" "node=research-1 role=reviewer" "research: 役割を差し替えられる"

dry research >/dev/null 2>&1
assert_eq "$?" "2" "research: topic が無いと 2 で終わる"

# fanout: 項目の数だけ + 統合 1 つ。
out="$(dry fanout --arg 'items=["a.ts","b.ts","c.ts"]' --arg task=型を洗い出す)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=fanout-')" "3" "fanout: 項目の数だけノードを作る"
assert_contains "$out" "node=fanout-1 role=researcher" "fanout: 項目は researcher"
assert_contains "$out" "node=synthesis role=synthesizer" "fanout: 統合は synthesizer"

dry fanout --arg task=x >/dev/null 2>&1
assert_eq "$?" "2" "fanout: items が無いと 2 で終わる"

# decide: 案 3 つ + 採点 1 つ。
out="$(dry decide --arg problem=課題)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=candidate-')" "3" "decide: 案の数だけノードを作る"
assert_contains "$out" "node=candidate-1 role=researcher" "decide: 案は researcher"
assert_contains "$out" "node=verdict role=judge" "decide: 採点は judge"

dry decide >/dev/null 2>&1
assert_eq "$?" "2" "decide: problem が無いと 2 で終わる"

# debate: 立場 2 つ + 裁定 1 つ。
out="$(dry debate --arg proposal=提案)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=position-')" "2" "debate: 立場の数だけノードを作る"
assert_contains "$out" "node=position-1 role=researcher" "debate: 立場は researcher"
assert_contains "$out" "node=verdict role=judge" "debate: 裁定は judge"

dry debate >/dev/null 2>&1
assert_eq "$?" "2" "debate: proposal が無いと 2 で終わる"

# review: 観点 3 つ + 統合 1 つ。
out="$(dry review --arg requirements=req.md --arg review_file=diff.md)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=review-')" "3" "review: 観点の数だけノードを作る"
assert_contains "$out" "node=review-1 role=reviewer" "review: 観点は reviewer"
assert_contains "$out" "node=final role=reviewer" "review: 統合も reviewer"

dry review --arg requirements=req.md >/dev/null 2>&1
assert_eq "$?" "2" "review: review_file が無いと 2 で終わる"

# triage: 観点 4 つ + 裁定 1 つ。
out="$(dry triage --arg symptom=症状)"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=angle-')" "4" "triage: 観点の数だけノードを作る"
assert_contains "$out" "node=angle-1 role=researcher" "triage: 観点は researcher"
assert_contains "$out" "node=verdict role=judge" "triage: 裁定は judge"

out="$(dry triage --arg symptom=症状 --arg 'angles=["a","b"]')"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=angle-')" "2" "triage: 観点を差し替えられる"

dry triage >/dev/null 2>&1
assert_eq "$?" "2" "triage: symptom が無いと 2 で終わる"

dry triage --arg symptom=症状 --arg angle=x >/dev/null 2>&1
assert_eq "$?" "2" "triage: 宣言に無い引数は 2 で終わる"

# --- 本実行の経路（--dry-run 無し）---
# 並行して起動したノードの出力を統合ノードが受け取ること、1 つ落ちたら run 全体が
# 止まることを、偽の paseo で確かめる。実エージェントは 1 つも起動しない。
live() {
  MAD_RECIPES_DIR="$SRC/recipes" \
  MAD_DEFS_DIR="$FIXTURE/defs" \
  MAD_PASEO_BIN="$FIXTURE/bin/paseo" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  FAKE_DIR="$FIXTURE/paseo" \
  bash "$FIXTURE/scripts/mad-run" "$@"
}

# mad-run は標準エラーに run の id を出す。同じ秒に作られた run と取り違えないよう、
# ディレクトリの新しさではなく id で run ディレクトリを引く。
run_dir_from() {
  local id
  id="$(grep -o '[0-9]\{8\}T[0-9]\{6\}-[0-9a-f]\{6\}' "$1" | head -1)"
  printf '%s' "$FIXTURE/repo/_cellfusion/mad/$id"
}

out="$(live research --arg topic=対象 \
  --arg 'perspectives=["観点A","観点B","観点C"]' 2>"$FIXTURE/live-ok.err")"
assert_eq "$?" "0" "本実行: すべてのノードが成功すると 0 で終わる"
assert_contains "$out" "出力 synthesis" "本実行: 統合ノードの JSON を標準出力に出す"

run_dir="$(run_dir_from "$FIXTURE/live-ok.err")"
prompt="$(cat "$run_dir/synthesis.prompt")"
for n in 1 2 3; do
  assert_contains "$prompt" "\"node\": \"research-$n\"" "本実行: 統合プロンプトに research-$n が入る"
  assert_contains "$prompt" "出力 research-$n" "本実行: 統合プロンプトに research-$n の出力が入る"
done

# 3 つの mad-route が同じキャッシュに同時に書く。別名を経由するので、残骸も壊れた内容も出ない。
assert_eq "$(ls "$run_dir/.cache" | grep -c '\.json\.[0-9][0-9]*$')" \
          "0" "本実行: キャッシュの一時ファイルを残さない"
assert_eq "$(jq -e type "$run_dir/.cache/providers.json" >/dev/null 2>&1 && echo yes || echo no)" \
          "yes" "本実行: 同時に書いたキャッシュが JSON として読める"

# シェル関数への環境変数の前置は bash では呼び出し後も残るので、subshell に閉じる。
( export FAKE_FAIL_MARK=観点B
  live research --arg topic=対象 \
    --arg 'perspectives=["観点A","観点B","観点C"]' >/dev/null 2>"$FIXTURE/live-ng.err" )
status=$?
err="$(cat "$FIXTURE/live-ng.err")"
assert_eq "$status" "1" "本実行: 1 つ落ちると非ゼロで終わる"
assert_contains "$err" "research-2" "本実行: 失敗したノードの名前を出す"
assert_contains "$err" "boom" "本実行: 失敗したノードの標準エラーの末尾を出す"
assert_contains "$err" "_cellfusion/mad/" "本実行: run ディレクトリのパスを出す"

run_dir="$(run_dir_from "$FIXTURE/live-ng.err")"
assert_eq "$([ -f "$run_dir/synthesis.json" ] && echo yes || echo no)" \
          "no" "本実行: 失敗したら統合ノードを走らせない"

# ノードごとの状態ファイルが残る。
node_field() { sed -n "s/^$2=//p" "$1"; }

# implement: worktree を作り、実装とレビューを回す。
out="$(dry implement --arg 'requirements=要件の本文')"
assert_contains "$out" "node=implement-1 role=implementer" "implement: 実装は implementer"
assert_contains "$out" "node=review-1 role=reviewer" "implement: レビューは reviewer"
assert_contains "$out" "workspace=dry-run" "implement: dry-run では workspace を作らない"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=implement-')" "1" \
  "implement: dry-run は 1 ラウンドで止まる"

dry implement >/dev/null 2>&1
assert_eq "$?" "2" "implement: requirements が無いと 2 で終わる"

# max_rounds が 1 以上の整数でないと、FAIL が続く限りループが終わらない。
for v in 0 abc; do
  dry implement --arg 'requirements=要件' --arg "max_rounds=$v" >/dev/null 2>&1
  assert_eq "$?" "2" "implement: max_rounds=$v は 2 で終わる"
done

# HEAD が detached だと base が決まらないので 2 で終わる。
( export FAKE_BRANCH=""
  dry implement --arg 'requirements=要件' >/dev/null 2>&1 )
assert_eq "$?" "2" "implement: base のブランチが決まらないと 2 で終わる"

out="$(live implement --arg 'requirements=要件の本文' 2>"$FIXTURE/impl-ok.err")"
assert_eq "$?" "0" "implement: PASS なら 0 で終わる"
assert_eq "$(printf '%s' "$out" | jq -r '.status')" "PASS" "implement: status を返す"
assert_eq "$(printf '%s' "$out" | jq -r '.rounds')" "1" "implement: PASS なら 1 ラウンド"
assert_eq "$(printf '%s' "$out" | jq -r '.workspaceId')" "wks_fake" \
  "implement: workspace の id を返す"
assert_contains "$(printf '%s' "$out" | jq -r '.branch')" "mad/" "implement: ブランチ名を返す"
assert_eq "$(printf '%s' "$out" | jq -r '.changedFiles[0]')" "a.txt" \
  "implement: 変更したファイルを返す"

run_dir="$(run_dir_from "$FIXTURE/impl-ok.err")"
assert_eq "$(node_field "$run_dir/implement-1.state" workspace)" "wks_fake" \
  "implement: ノードの状態に workspace を書く"
assert_eq "$(jq -r '.base' "$run_dir/run.json")" "main" "implement: run.json に base を書く"
assert_contains "$(cat "$run_dir/review-1.prompt")" "+変更した行" \
  "implement: レビューのプロンプトに差分を埋める"

# FAIL なら max_rounds まで回る。
( export FAKE_REVIEW_STATUS=FAIL
  live implement --arg 'requirements=要件' --arg max_rounds=2 \
    >"$FIXTURE/impl-ng.out" 2>"$FIXTURE/impl-ng.err" )
assert_eq "$(jq -r '.rounds' "$FIXTURE/impl-ng.out")" "2" \
  "implement: FAIL なら max_rounds まで回る"
run_dir="$(run_dir_from "$FIXTURE/impl-ng.err")"
assert_contains "$(cat "$run_dir/implement-2.prompt")" "指摘" \
  "implement: 2 ラウンド目のプロンプトに指摘を渡す"

# 実装役がコミットしなかったとき、レビュー役に空のコードブロックを渡さない。
( export FAKE_DIFF_MODE=empty
  live implement --arg 'requirements=要件' >/dev/null 2>"$FIXTURE/impl-nodiff.err" )
run_dir="$(run_dir_from "$FIXTURE/impl-nodiff.err")"
assert_contains "$(cat "$run_dir/review-1.prompt")" "（差分が無い）" \
  "implement: 差分が無いことをレビューのプロンプトに書く"

# git が差分を返せないときは、レビュー役を起こさずに run を止める。
( export FAKE_DIFF_MODE=fail
  live implement --arg 'requirements=要件' >/dev/null 2>"$FIXTURE/impl-diffng.err" )
assert_eq "$?" "1" "implement: 差分を取れないと非ゼロで終わる"
err="$(cat "$FIXTURE/impl-diffng.err")"
assert_contains "$err" "差分を取れない" "implement: 差分を取れない理由を出す"
run_dir="$(run_dir_from "$FIXTURE/impl-diffng.err")"
assert_eq "$([ -f "$run_dir/review-1.json" ] && echo yes || echo no)" "no" \
  "implement: 差分を取れないとレビュー役を走らせない"

# spike: 方針ごとに worktree を作り、並行実装して 1 つ選ぶ。
out="$(dry spike --arg 'requirements=要件の本文')"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=spike-')" "3" "spike: 方針の数だけノードを作る"
assert_contains "$out" "node=spike-1 role=implementer" "spike: 実装は implementer"
assert_contains "$out" "node=verdict role=judge" "spike: 裁定は judge"
assert_contains "$out" "workspace=dry-run" "spike: dry-run では workspace を作らない"

out="$(dry spike --arg 'requirements=要件' --arg 'approaches=["a","b"]')"
assert_eq "$(printf '%s\n' "$out" | grep -c '^node=spike-')" "2" "spike: 方針を差し替えられる"

dry spike >/dev/null 2>&1
assert_eq "$?" "2" "spike: requirements が無いと 2 で終わる"

# refine: cwd の対象ファイルを批評して改稿する。
printf '草稿の本文\n' > "$FIXTURE/repo/draft.md"

refine_run() {
  ( cd "$FIXTURE/repo" && MAD_RECIPES_DIR="$SRC/recipes" MAD_DEFS_DIR="$FIXTURE/defs" \
    MAD_PASEO_BIN="$FIXTURE/bin/paseo" MAD_GIT_BIN="$FIXTURE/bin/git" \
    FAKE_DIR="$FIXTURE/paseo" \
    bash "$FIXTURE/scripts/mad-run" refine "$@" )
}

out="$(refine_run --arg file=draft.md --arg goal=読みやすくする --dry-run 2>/dev/null)"
assert_contains "$out" "node=critique-1 role=reviewer" "refine: 批評は reviewer"
assert_contains "$out" "workspace=none" "refine: workspace を作らない"

refine_run --arg goal=x --dry-run >/dev/null 2>&1
assert_eq "$?" "2" "refine: file が無いと 2 で終わる"
refine_run --arg file=nosuch.md --arg goal=x --dry-run >/dev/null 2>&1
assert_eq "$?" "2" "refine: 対象ファイルが無いと 2 で終わる"

for v in 0 abc; do
  refine_run --arg file=draft.md --arg goal=x --arg "max_rounds=$v" --dry-run \
    >/dev/null 2>&1
  assert_eq "$?" "2" "refine: max_rounds=$v は 2 で終わる"
done

out="$(refine_run --arg file=draft.md --arg goal=読みやすくする 2>"$FIXTURE/refine-ok.err")"
assert_eq "$?" "0" "refine: PASS なら 0 で終わる"
assert_eq "$(printf '%s' "$out" | jq -r '.status')" "PASS" "refine: status を返す"
assert_eq "$(printf '%s' "$out" | jq -r '.revisions')" "0" "refine: PASS なら改稿しない"
assert_eq "$(printf '%s' "$out" | jq -r '.file')" "draft.md" "refine: 対象ファイルを返す"

( export FAKE_REVIEW_STATUS=FAIL
  refine_run --arg file=draft.md --arg goal=x --arg max_rounds=2 \
    >"$FIXTURE/refine-ng.out" 2>"$FIXTURE/refine-ng.err" )
assert_eq "$(jq -r '.revisions' "$FIXTURE/refine-ng.out")" "2" \
  "refine: FAIL なら max_rounds 回改稿する"
run_dir="$(run_dir_from "$FIXTURE/refine-ng.err")"
assert_eq "$(node_field "$run_dir/revise-1.state" role)" "writer" "refine: 改稿は writer"
assert_eq "$([ -f "$run_dir/refine-1.before" ] && echo yes || echo no)" "yes" \
  "refine: 改稿の前のファイルを残す"
assert_eq "$(ls "$run_dir" | grep -c '^critique-[0-9]*\.json$')" "3" \
  "refine: 改稿 2 回のあいだに批評を 3 回行う"

out="$(live spike --arg 'requirements=要件' --arg 'approaches=["案A","案B"]' \
  2>"$FIXTURE/spike.err")"
assert_eq "$?" "0" "spike: すべて成功すると 0 で終わる"
assert_eq "$(printf '%s' "$out" | jq -r '.winner')" "spike-1" "spike: 選んだ案を返す"
assert_eq "$(printf '%s' "$out" | jq -r '.candidates | length')" "2" "spike: 案の一覧を添える"
assert_eq "$(printf '%s' "$out" | jq -r '.candidates[0].workspaceId')" "wks_fake" \
  "spike: 案ごとに workspace の id を添える"
assert_eq "$(printf '%s' "$out" | jq -r '.candidates[1].approach')" "案B" \
  "spike: 案ごとに方針を添える"
run_dir="$(run_dir_from "$FIXTURE/spike.err")"
assert_contains "$(cat "$run_dir/verdict.prompt")" "+変更した行" \
  "spike: 裁定のプロンプトに差分を埋める"
assert_eq "$(grep -c 'wks_fake' "$run_dir/workspaces.txt")" "2" \
  "spike: 方針の数だけ workspace を作る"

( export FAKE_DIFF_MODE=fail
  live spike --arg 'requirements=要件' --arg 'approaches=["案A"]' \
    >/dev/null 2>"$FIXTURE/spike-diffng.err" )
assert_eq "$?" "1" "spike: 差分を取れないと非ゼロで終わる"
run_dir="$(run_dir_from "$FIXTURE/spike-diffng.err")"
assert_eq "$([ -f "$run_dir/verdict.json" ] && echo yes || echo no)" "no" \
  "spike: 差分を取れないと裁定役を走らせない"

out="$(live research --arg topic=対象 \
  --arg 'perspectives=["観点A","観点B"]' 2>"$FIXTURE/live-state.err")"
run_dir="$(run_dir_from "$FIXTURE/live-state.err")"
assert_eq "$(node_field "$run_dir/research-1.state" state)" "ok" \
  "本実行: 成功したノードの状態は ok"
assert_eq "$(node_field "$run_dir/research-1.state" role)" "researcher" \
  "本実行: 状態ファイルに役割を書く"
assert_eq "$(node_field "$run_dir/synthesis.state" state)" "ok" \
  "本実行: 統合ノードの状態も残る"
started="$(node_field "$run_dir/synthesis.state" startedAt)"
assert_not_contains "|$started|" "||" "本実行: 状態ファイルに開始時刻を書く"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
