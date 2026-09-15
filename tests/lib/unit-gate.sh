#!/usr/bin/env bash
# unit gate の判定 file と decision request を 0600 の regular file として扱う。

_unit_gate_require_private_regular_file() {
  local file_path="$1"
  test -f "$file_path" || return 1
  test ! -L "$file_path" || return 1
  test "$(stat -f '%HT:%Lp' "$file_path" 2>/dev/null)" = "Regular File:600"
}

_unit_gate_sync_file() {
  /usr/bin/perl -e '
    open my $file, "+<", $ARGV[0] or exit 1;
    $file->sync or exit 1;
  ' "$1"
}

_write_unit_gate_private_file() {
  local target_path="${1:-}" contents="${2:-}"
  local target_directory target_basename temporary
  case "$target_path" in /*) : ;; *) return 2 ;; esac
  test ! -d "$target_path" || return 2
  target_directory="$(dirname "$target_path")" || return 2
  target_basename="$(basename "$target_path")" || return 2
  mkdir -p "$target_directory" || return 2
  temporary="$(umask 077; mktemp "$target_directory/.${target_basename}.tmp.XXXXXX")" || return 2
  if ! ( umask 077
    printf '%s' "$contents" > "$temporary" &&
      chmod 600 "$temporary" &&
      _unit_gate_sync_file "$temporary"
  ); then
    rm -f "$temporary"
    return 2
  fi
  if ! mv -f "$temporary" "$target_path"; then
    rm -f "$temporary"
    return 2
  fi
  _unit_gate_require_private_regular_file "$target_path" || return 2
}

write_unit_decision() {
  local decision_path="${1:-}" decision_value="${2:-}"
  local decision_contents
  case "$decision_path" in /*) : ;; *) return 2 ;; esac
  case "$decision_value" in
    continue|rollback|decision_request|approved-success) : ;;
    *) return 2 ;;
  esac
  printf -v decision_contents '%s\n' "$decision_value"
  _write_unit_gate_private_file "$decision_path" "$decision_contents"
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
  local request_contents
  case "$request_path" in /*) : ;; *) return 2 ;; esac
  printf -v request_contents '# Decision request\n\n## Question\n\n%s\n\n## Options\n\n- %s\n- %s\n' \
    "$question" "$option_one" "$option_two"
  _write_unit_gate_private_file "$request_path" "$request_contents"
}
