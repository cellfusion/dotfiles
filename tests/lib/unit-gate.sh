#!/usr/bin/env bash
# unit gate の判定 file と decision request を 0600 の regular file として扱う。

write_unit_decision() {
  local decision_path="${1:-}" decision_value="${2:-}"
  case "$decision_path" in /*) : ;; *) return 2 ;; esac
  case "$decision_value" in
    continue|rollback|decision_request|approved-success) : ;;
    *) return 2 ;;
  esac
  test ! -d "$decision_path" || return 2
  mkdir -p "$(dirname "$decision_path")" || return 2
  ( umask 077; printf '%s\n' "$decision_value" > "$decision_path.tmp" ) || return 2
  chmod 600 "$decision_path.tmp" || return 2
  mv "$decision_path.tmp" "$decision_path"
}

require_unit_decision() {
  local decision_path="${1:-}" expected_value="${2:-}"
  test -f "$decision_path" || return 1
  test ! -L "$decision_path" || return 1
  test "$(stat -f '%Lp' "$decision_path")" = "600" || return 1
  printf '%s\n' "$expected_value" | cmp -s - "$decision_path"
}

write_decision_request() {
  local request_path="${1:-}" question="${2:-}" option_one="${3:-}" option_two="${4:-}"
  case "$request_path" in /*) : ;; *) return 2 ;; esac
  test ! -d "$request_path" || return 2
  mkdir -p "$(dirname "$request_path")" || return 2
  ( umask 077
    printf '# Decision request\n\n## Question\n\n%s\n\n## Options\n\n- %s\n- %s\n' \
      "$question" "$option_one" "$option_two" > "$request_path.tmp" ) || return 2
  chmod 600 "$request_path.tmp" || return 2
  mv "$request_path.tmp" "$request_path"
}
