#!/usr/bin/env bash
# mad-agent が paseo run に渡す引数と、出力の落とし方を検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

SRC="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/defs/prompts" "$FIXTURE/defs/schemas" "$FIXTURE/bin" "$FIXTURE/scripts" "$FIXTURE/paseo"

# scripts を実行名で置く。mad-agent は同じディレクトリの mad-route を呼ぶ。
cp "$SRC/executable_mad-route" "$FIXTURE/scripts/mad-route"
cp "$SRC/executable_mad-agent" "$FIXTURE/scripts/mad-agent"
chmod +x "$FIXTURE/scripts/mad-route" "$FIXTURE/scripts/mad-agent"

for f in manifests paseo-providers paseo-routing paseo-project-routing; do
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/$f.json\" . }}" > "$FIXTURE/defs/$f.json"
done
printf 'あなたは調査役である。\n' > "$FIXTURE/defs/prompts/researcher.md"
chezmoi execute-template --source "$CHEZMOI_SOURCE" \
  '{{ includeTemplate "agent-defs/schemas/researcher.json" . }}' > "$FIXTURE/defs/schemas/researcher.json"

# 偽の paseo。引数を記録し、固定の JSON を返す。
cat > "$FIXTURE/bin/paseo" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "provider ls") cat "$FAKE_DIR/providers.json"; exit 0 ;;
  "provider models") cat "$FAKE_DIR/models-$3.json"; exit 0 ;;
esac
printf '%s\n' "$@" > "$FAKE_DIR/argv.txt"
if [ "${FAKE_FAIL:-0}" = "1" ]; then
  printf 'boom\n' >&2
  exit 3
fi
if [ "${FAKE_EMPTY:-0}" = "1" ]; then
  exit 0
fi
cat "$FAKE_DIR/out.json"
FAKE
chmod +x "$FIXTURE/bin/paseo"

cat > "$FIXTURE/bin/git" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --show-toplevel") printf '/tmp/repo\n' ;;
  "remote get-url origin") printf '\n' ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git"

cat > "$FIXTURE/paseo/providers.json" <<'JSON'
[ { "provider": "codex", "status": "available", "enabled": "Enabled" } ]
JSON
cat > "$FIXTURE/paseo/models-codex.json" <<'JSON'
[ { "id": "gpt-5.6-luna", "thinkingOptionIds": ["low","medium","high"] } ]
JSON
cat > "$FIXTURE/paseo/out.json" <<'JSON'
{ "summary": "s", "findings": [], "sources": [], "cannotVerify": null }
JSON

printf '調べる対象は X である。\n' > "$FIXTURE/prompt.txt"

agent() {
  MAD_DEFS_DIR="$FIXTURE/defs" \
  MAD_PASEO_BIN="$FIXTURE/bin/paseo" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  FAKE_DIR="$FIXTURE/paseo" \
  bash "$FIXTURE/scripts/mad-agent" "$@"
}

agent --role researcher --prompt-file "$FIXTURE/prompt.txt" \
      --out "$FIXTURE/out.json" --log "$FIXTURE/out.log" \
      --cwd "$FIXTURE" --timeout 60 --title "mad/run1/n1"
status=$?
assert_eq "$status" "0" "成功すると終了コード 0"

argv="$(cat "$FIXTURE/paseo/argv.txt")"
assert_contains "$argv" "run" "paseo run を呼ぶ"
assert_contains "$argv" "--provider" "provider を渡す"
assert_contains "$argv" "codex" "解決した provider を渡す"
assert_contains "$argv" "gpt-5.6-luna" "解決した model を渡す"
assert_contains "$argv" "--thinking" "thinking を渡す"
assert_contains "$argv" "--mode" "mode を渡す"
assert_contains "$argv" "--output-schema" "スキーマを渡す"
assert_contains "$argv" "researcher.json" "役割のスキーマを渡す"
assert_contains "$argv" "--wait-timeout" "タイムアウトを渡す"
assert_contains "$argv" "60s" "秒に s を付けて渡す"
assert_contains "$argv" "mad/run1/n1" "title を渡す"
assert_contains "$argv" "あなたは調査役である。" "役割の system prompt を結合する"
assert_contains "$argv" "調べる対象は X である。" "レシピのプロンプトを結合する"

out="$(cat "$FIXTURE/out.json")"
assert_contains "$out" "summary" "標準出力を out に落とす"

# paseo が失敗したら同じ終了コードで終わる。
# シェル関数への環境変数の前置は bash では呼び出し後も残るので、subshell に閉じる。
( export FAKE_FAIL=1
  agent --role researcher --prompt-file "$FIXTURE/prompt.txt" \
    --out "$FIXTURE/out2.json" --log "$FIXTURE/out2.log" >/dev/null 2>&1 )
assert_eq "$?" "3" "paseo の終了コードをそのまま返す"
assert_contains "$(cat "$FIXTURE/out2.log")" "boom" "標準エラーを log に落とす"

# 出力が空なら失敗する。
( export FAKE_EMPTY=1
  agent --role researcher --prompt-file "$FIXTURE/prompt.txt" \
    --out "$FIXTURE/out3.json" --log "$FIXTURE/out3.log" >/dev/null 2>&1 )
assert_eq "$?" "1" "構造化出力が空なら失敗する"

# 必須の引数が無いと 2 で終わる。
agent --role researcher >/dev/null 2>&1
assert_eq "$?" "2" "必須の引数が無いと 2 で終わる"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
