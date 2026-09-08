#!/usr/bin/env bash
set -u
. "$(dirname "$0")/lib/assert.sh"
SCRIPT="$CHEZMOI_SOURCE/private_dot_agents/skills/_shared/scripts/executable_agent-docs-dir"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/root" "$TMP/repo/.git" "$TMP/ws/cellfusion/Hoge/.git" "$TMP/bin-ssh" "$TMP/bin-https" "$TMP/bin-noremote" "$TMP/bin-outside"
cat > "$TMP/bin-ssh/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-common-dir") printf '%s\n' "$TMP/repo/.git" ;;
  "remote get-url origin") printf 'git@github.com:cellfusion/dotfiles.git\n' ;;
  *) exit 1 ;;
esac
FAKE
cat > "$TMP/bin-https/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-common-dir") printf '%s\n' "$TMP/repo/.git" ;;
  "remote get-url origin") printf 'https://github.com/cellfusion/dotfiles.git\n' ;;
  *) exit 1 ;;
esac
FAKE
cat > "$TMP/bin-noremote/git" <<FAKE
#!/usr/bin/env bash
case "\$*" in
  "rev-parse --git-common-dir") printf '%s\n' "$TMP/ws/cellfusion/Hoge/.git" ;;
  "remote get-url origin") printf '\n' ;;
  *) exit 1 ;;
esac
FAKE
cat > "$TMP/bin-outside/git" <<'FAKE'
#!/usr/bin/env bash
exit 128
FAKE
chmod +x "$TMP/bin-ssh/git" "$TMP/bin-https/git" "$TMP/bin-noremote/git" "$TMP/bin-outside/git"
run() { local bin="$1"; shift; AGENT_DOCS_ROOT="$TMP/root" PATH="$bin:$PATH" bash "$SCRIPT" "$@"; }
out="$(run "$TMP/bin-ssh")"; assert_eq "$out" "$TMP/root/cellfusion/dotfiles" "SSH 形式"
out="$(run "$TMP/bin-https")"; assert_eq "$out" "$TMP/root/cellfusion/dotfiles" "HTTPS 形式"
out="$(run "$TMP/bin-noremote")"; assert_eq "$out" "$TMP/root/cellfusion/Hoge" "remote 無し"
out="$(run "$TMP/bin-outside" 2>"$TMP/outside.err")"; status=$?
assert_eq "$status" "1" "リポジトリ外"
assert_eq "$out" "" "リポジトリ外の標準出力"
assert_contains "$(cat "$TMP/outside.err")" "git" "標準エラー"
out="$(run "$TMP/bin-ssh" specs)"; assert_eq "$out" "$TMP/root/cellfusion/dotfiles/specs" "引数"
assert_eq "$([ -d "$out" ] && echo yes || echo no)" "yes" "引数ディレクトリ"
out="$(run "$TMP/bin-ssh" sdd/2026-09-08-foo)"; assert_eq "$out" "$TMP/root/cellfusion/dotfiles/sdd/2026-09-08-foo" "区切り"
out="$(run "$TMP/bin-ssh" sdd 2026-09-08-bar)"; assert_eq "$out" "$TMP/root/cellfusion/dotfiles/sdd/2026-09-08-bar" "複数引数"
out="$(run "$TMP/bin-ssh")"; assert_eq "$([ -d "$out" ] && echo yes || echo no)" "yes" "根"
assert_eq "$(find "$TMP/root" -name .gitignore | wc -l | tr -d ' ')" "0" "gitignore 無し"
real="$TMP/real"; mkdir -p "$real/cellfusion/Fuga/sub"; git -C "$real/cellfusion/Fuga" init -q
out="$(cd "$real/cellfusion/Fuga/sub" && AGENT_DOCS_ROOT="$TMP/root2" bash "$SCRIPT")"
assert_eq "$out" "$TMP/root2/cellfusion/Fuga" "相対 common dir"
printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"

