#!/usr/bin/env bash
set -u
source "$(dirname "$0")/lib/assert.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
cat > "$tmp/bin/swift" <<'SH'
#!/bin/sh
printf '%s' "$NOTCH_FRAME"
SH
cat > "$tmp/bin/yabai" <<'SH'
#!/bin/sh
if [ "$2" = query ]; then
  printf '%s\n' '[{"frame":{"x":0,"y":0,"w":1512,"h":982},"spaces":[1,2]},{"frame":{"x":1512,"y":0,"w":1920,"h":1080},"spaces":[3]}]'
else
  printf '%s\n' "$*" >> "$PADDING_LOG"
fi
SH
chmod +x "$tmp/bin/swift" "$tmp/bin/yabai"
export PATH="$tmp/bin:$PATH" PADDING_LOG="$tmp/padding"
export NOTCH_FRAME
NOTCH_FRAME="$(printf '0\t0\t1512\t982')"
sh "$CHEZMOI_SOURCE/private_dot_config/yabai/executable_display-padding"
assert_eq "$(cat "$PADDING_LOG")" '-m config top_padding 38
-m config --space 1 top_padding 0
-m config --space 2 top_padding 0
-m config --space 3 top_padding 38' 'notched display reserves no extra space; external display reserves 38px'
NOTCH_FRAME=''
: > "$PADDING_LOG"
status=0
sh "$CHEZMOI_SOURCE/private_dot_config/yabai/executable_display-padding" || status=$?
assert_eq "$status" 0 'non-notched and external-only setups succeed'
assert_eq "$(cat "$PADDING_LOG")" '-m config top_padding 38
-m config --space 1 top_padding 38
-m config --space 2 top_padding 38
-m config --space 3 top_padding 38' 'without a notch every space reserves 38px'
assert_summary
