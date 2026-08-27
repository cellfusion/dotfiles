#!/usr/bin/env bash
# テスト用の assert 関数。各テストスクリプトから source して使う。

TESTS_FAILED=0
TESTS_RUN=0

# chezmoi source ディレクトリ。テストはどこから実行されてもここを見る。
CHEZMOI_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

_fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  FAIL: %s\n' "$1" >&2
  if [ -n "${2:-}" ]; then
    printf '    %s\n' "$2" >&2
  fi
}

_pass() {
  printf '  ok: %s\n' "$1"
}

assert_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) _pass "$3" ;;
    *) _fail "$3" "期待した文字列が無い: $2" ;;
  esac
}

assert_not_contains() {
  TESTS_RUN=$((TESTS_RUN + 1))
  case "$1" in
    *"$2"*) _fail "$3" "あってはならない文字列がある: $2" ;;
    *) _pass "$3" ;;
  esac
}

assert_eq() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$1" = "$2" ]; then
    _pass "$3"
  else
    _fail "$3" "期待: $2 / 実際: $1"
  fi
}

# .chezmoitemplates/<name> を tool=<tool> 付きで展開する。
render_template() {
  chezmoi execute-template --source "$CHEZMOI_SOURCE" \
    "{{ includeTemplate \"$1\" (merge (dict \"tool\" \"$2\") .) }}"
}
