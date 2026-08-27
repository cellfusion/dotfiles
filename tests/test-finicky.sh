#!/usr/bin/env bash
# finicky.js.tmpl が data からルールを組み立てることを検証する。
set -u
# shellcheck source=lib/assert.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"

TMPL="$CHEZMOI_SOURCE/private_dot_config/finicky/finicky.js.tmpl"

# ルールを 2 件与えると、その 2 件が handlers に並ぶ。
cfg="$(mktemp)"
cat > "$cfg" <<'EOF'
[data.browser]
    defaultBrowser = "Google Chrome"
[[data.browser.rules]]
    match = "example.test"
    profile = "alpha"
[[data.browser.rules]]
    match = "other.test/*"
    profile = "beta"
EOF
out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml < "$TMPL")"
rm -f "$cfg"

assert_contains "$out" 'defaultBrowser: "Google Chrome"' "defaultBrowser を data から取る"
assert_contains "$out" '"example.test"' "1件目の match を出す"
assert_contains "$out" 'profile: "alpha"' "1件目の profile を出す"
assert_contains "$out" '"other.test/*"' "2件目の match を出す"
assert_contains "$out" 'profile: "beta"' "2件目の profile を出す"

# ルールが 0 件でも壊れず、handlers が空配列になる。
empty_cfg="$(mktemp)"
cat > "$empty_cfg" <<'EOF'
[data.browser]
    defaultBrowser = "Safari"
EOF
empty_out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$empty_cfg" --config-format toml < "$TMPL")"
rm -f "$empty_cfg"

assert_contains "$empty_out" 'defaultBrowser: "Safari"' "ルール0件でも defaultBrowser を出す"
assert_contains "$empty_out" 'handlers: [' "ルール0件でも handlers を出す"
assert_not_contains "$empty_out" 'profile:' "ルール0件では profile 行を出さない"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
