#!/bin/bash

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

case "$FILE_PATH" in
  *.ts|*.tsx)
    npx tsc --noEmit 2>&1 | head -20
    ;;
  *.rs)
    cargo check 2>&1 | head -20
    ;;
  *.py)
    python -m py_compile "$FILE_PATH" 2>&1
    ;;
esac

exit 0
