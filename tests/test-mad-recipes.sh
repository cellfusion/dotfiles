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
printf '{ "summary": "出力 %s" }\n' "${title##*/}"
FAKE
chmod +x "$FIXTURE/bin/paseo"

# 本実行は役割ごとの system prompt とスキーマを読む。
mkdir -p "$FIXTURE/defs/prompts" "$FIXTURE/defs/schemas"
for role in researcher synthesizer; do
  printf 'あなたは %s である。\n' "$role" > "$FIXTURE/defs/prompts/$role.md"
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/schemas/$role.json\" . }}" > "$FIXTURE/defs/schemas/$role.json"
done

cat > "$FIXTURE/bin/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --show-toplevel") printf '%s\n' "$FIXTURE/repo" ;;
  "remote get-url origin") printf '\n' ;;
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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
