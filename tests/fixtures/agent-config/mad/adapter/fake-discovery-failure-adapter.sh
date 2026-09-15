#!/usr/bin/env bash
set -u

case "${1:-}" in
  list-providers) exit 1 ;;
  *) exit 2 ;;
esac
