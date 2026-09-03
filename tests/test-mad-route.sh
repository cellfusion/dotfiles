#!/usr/bin/env bash
# mad-route が役割から provider / model / thinking / mode を解決することを検証する。
set -u
. "$(dirname "$0")/lib/assert.sh"

ROUTE="$CHEZMOI_SOURCE/private_dot_agents/skills/multi-agent-development/scripts/executable_mad-route"

FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/defs" "$FIXTURE/bin" "$FIXTURE/paseo"
for f in manifests paseo-providers paseo-routing paseo-project-routing; do
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"agent-defs/$f.json\" . }}" > "$FIXTURE/defs/$f.json"
done

# 偽の paseo。provider ls と provider models だけを返す。
cat > "$FIXTURE/bin/paseo" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "provider ls") cat "$FAKE_DIR/providers.json" ;;
  "provider models") cat "$FAKE_DIR/models-$3.json" 2>/dev/null || exit 1 ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/paseo"

# 偽の git。toplevel と remote を環境変数で差し替える。
cat > "$FIXTURE/bin/git" <<'FAKE'
#!/usr/bin/env bash
case "$*" in
  "rev-parse --show-toplevel") printf '%s\n' "${FAKE_TOPLEVEL:-/tmp/repo}" ;;
  "remote get-url origin") printf '%s\n' "${FAKE_REMOTE:-}" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/git"

# 別アカウント版の provider と、それを使う規則をフィクスチャに足す。描画された
# アセットは既定の 2 provider と 0 件の規則しか持たないので、ここで組み立てる。
jq '. + { "claude-acme": .claude, "codex-acme": .codex }' \
  "$FIXTURE/defs/paseo-providers.json" > "$FIXTURE/defs/providers.tmp"
mv "$FIXTURE/defs/providers.tmp" "$FIXTURE/defs/paseo-providers.json"
cat > "$FIXTURE/defs/paseo-project-routing.json" <<'JSON'
{ "rules": [ { "name": "acme",
               "match": { "remote": "github.com/acme/" },
               "providerMap": { "claude": "claude-acme", "codex": "codex-acme" } } ] }
JSON

cat > "$FIXTURE/paseo/providers.json" <<'JSON'
[
  { "provider": "claude", "status": "available", "enabled": "Enabled" },
  { "provider": "codex", "status": "available", "enabled": "Enabled" },
  { "provider": "claude-acme", "status": "available", "enabled": "Enabled" },
  { "provider": "codex-acme", "status": "available", "enabled": "Enabled" }
]
JSON
cat > "$FIXTURE/paseo/models-codex.json" <<'JSON'
[ { "id": "gpt-5.6-luna", "thinkingOptionIds": ["low","medium","high"] },
  { "id": "gpt-5.6-terra", "thinkingOptionIds": ["low","medium","high"] },
  { "id": "gpt-5.6-sol", "thinkingOptionIds": ["low","medium","high"] } ]
JSON
cp "$FIXTURE/paseo/models-codex.json" "$FIXTURE/paseo/models-codex-acme.json"
cat > "$FIXTURE/paseo/models-claude.json" <<'JSON'
[ { "id": "claude-sonnet-5", "thinkingOptionIds": ["low","medium","high","max"] },
  { "id": "claude-opus-5", "thinkingOptionIds": ["low","medium","high","max"] } ]
JSON
cp "$FIXTURE/paseo/models-claude.json" "$FIXTURE/paseo/models-claude-acme.json"

route() {
  MAD_DEFS_DIR="$FIXTURE/defs" \
  MAD_PASEO_BIN="$FIXTURE/bin/paseo" \
  MAD_GIT_BIN="$FIXTURE/bin/git" \
  FAKE_DIR="$FIXTURE/paseo" \
  bash "$ROUTE" "$@"
}

# 既定の候補が採られる。
out="$(route researcher)"
assert_contains "$out" "provider=codex" "researcher: 先頭候補の codex を採る"
assert_contains "$out" "model=gpt-5.6-luna" "researcher: work は luna"
assert_contains "$out" "thinking=high" "researcher: work は high"
assert_contains "$out" "mode=auto" "researcher: codex の read は auto"
assert_contains "$out" "access=read" "researcher: 読み取り専用"
assert_contains "$out" "rule=default" "researcher: 規則に一致しない"

out="$(route synthesizer)"
assert_contains "$out" "provider=claude" "synthesizer: claude を採る"
assert_contains "$out" "model=claude-opus-5" "synthesizer: think は opus"
assert_contains "$out" "mode=plan" "synthesizer: claude の read は plan"

out="$(route implementer)"
assert_contains "$out" "access=write" "implementer: 書き込み可"
assert_contains "$out" "mode=auto" "implementer: codex の write は auto"

# remote が一致すると providerMap が効く。
out="$(FAKE_REMOTE="git@github.com:acme/foo.git" route researcher)"
assert_contains "$out" "provider=codex-acme" "acme: providerMap で置換される"
assert_contains "$out" "rule=acme" "acme: 効いた規則を出す"

# path が一致しても効く。
cat > "$FIXTURE/defs/paseo-project-routing.json" <<'JSON'
{ "rules": [ { "name": "bypath", "match": { "path": "/tmp/repo" },
              "roles": { "researcher": [ { "provider": "claude" } ] } } ] }
JSON
out="$(route researcher)"
assert_contains "$out" "provider=claude" "bypath: roles の差し替えが効く"
assert_contains "$out" "rule=bypath" "bypath: 効いた規則を出す"

# 先頭候補が使えないと次の候補に落ちる。
cat > "$FIXTURE/defs/paseo-project-routing.json" <<'JSON'
{ "rules": [] }
JSON
cat > "$FIXTURE/paseo/providers.json" <<'JSON'
[ { "provider": "claude", "status": "available", "enabled": "Enabled" },
  { "provider": "codex", "status": "unavailable", "enabled": "Disabled" } ]
JSON
out="$(route researcher)"
assert_contains "$out" "provider=claude" "codex が使えないと claude に落ちる"

# model が実在しないと候補を飛ばす。
cat > "$FIXTURE/paseo/providers.json" <<'JSON'
[ { "provider": "claude", "status": "available", "enabled": "Enabled" },
  { "provider": "codex", "status": "available", "enabled": "Enabled" } ]
JSON
printf '[]\n' > "$FIXTURE/paseo/models-codex.json"
out="$(route researcher)"
assert_contains "$out" "provider=claude" "codex の model が無いと claude に落ちる"

# 候補が全滅すると失敗する。
printf '[]\n' > "$FIXTURE/paseo/models-claude.json"
if route researcher >/dev/null 2>&1; then
  _fail "候補が全滅したら失敗する" "終了ステータスが 0 だった"
else
  _pass "候補が全滅したら失敗する"
fi
TESTS_RUN=$((TESTS_RUN + 1))

# 未知の役割は失敗する。
if route no-such-role >/dev/null 2>&1; then
  _fail "未知の役割は失敗する" "終了ステータスが 0 だった"
else
  _pass "未知の役割は失敗する"
fi
TESTS_RUN=$((TESTS_RUN + 1))

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
