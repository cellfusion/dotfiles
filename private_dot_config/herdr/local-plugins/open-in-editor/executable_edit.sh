#!/usr/bin/env bash
# Overlay pane entrypoint: opens Markdown in Leaf; other files in nvim with optional line.
set -euo pipefail

[ -n "${EDIT_FILE:-}" ] || { echo "EDIT_FILE not set" >&2; exec "${SHELL:-/bin/sh}"; }

case "$EDIT_FILE" in
  *.[mM][dD]) exec leaf "$EDIT_FILE" ;;
esac

if [ -n "${EDIT_LINE:-}" ]; then
  exec nvim "+${EDIT_LINE}" "${EDIT_FILE}"
fi
exec nvim "${EDIT_FILE}"
