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

cat > "$FIXTURE/bin/paseo" <<'FAKE'
#!/usr/bin/env bash
case "$1 $2" in
  "provider ls") cat "$FAKE_DIR/providers.json" ;;
  "provider models") cat "$FAKE_DIR/models.json" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FIXTURE/bin/paseo"

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

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
