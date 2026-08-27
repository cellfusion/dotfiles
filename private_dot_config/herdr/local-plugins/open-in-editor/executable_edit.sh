#!/usr/bin/env bash
# Overlay pane entrypoint: opens EDIT_FILE in nvim, jumping to EDIT_LINE if set.
set -euo pipefail

[ -n "${EDIT_FILE:-}" ] || { echo "EDIT_FILE not set" >&2; exec "${SHELL:-/bin/sh}"; }

if [ -n "${EDIT_LINE:-}" ]; then
  exec nvim "+${EDIT_LINE}" "${EDIT_FILE}"
fi
exec nvim "${EDIT_FILE}"
