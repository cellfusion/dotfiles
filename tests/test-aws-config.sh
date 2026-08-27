#!/usr/bin/env bash
# aws/config.tmpl が data からプロファイルを組み立てることを検証する。
set -u
# shellcheck source=lib/assert.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/assert.sh"

TMPL="$CHEZMOI_SOURCE/private_dot_config/aws/config.tmpl"

cfg="$(mktemp)"
cat > "$cfg" <<'EOF'
[data.aws]
    opAccount = "example.1password.com"
    region = "ap-northeast-1"
[[data.aws.profiles]]
    name = "default"
    opPath = "op://Vault/Item/default"
[[data.aws.profiles]]
    name = "alpha"
    opPath = "op://Vault/Item/alpha"
EOF
out="$(chezmoi execute-template --source "$CHEZMOI_SOURCE" --config "$cfg" --config-format toml < "$TMPL")"
rm -f "$cfg"

assert_contains "$out" '[default]' "default は [default] として書く"
assert_not_contains "$out" '[profile default]' "default に profile 接頭辞を付けない"
assert_contains "$out" '[profile alpha]' "default 以外は [profile <name>] にする"
assert_contains "$out" 'region = ap-northeast-1' "region を data から取る"
assert_contains "$out" 'op://Vault/Item/default' "default の op パスを出す"
assert_contains "$out" 'op://Vault/Item/alpha' "alpha の op パスを出す"
assert_contains "$out" '--account example.1password.com' "1Password アカウントを data から取る"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
