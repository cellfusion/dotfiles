#!/usr/bin/env bash
# terminal-resize の引数パースと dry-run 出力を検証する。
# 実際にウィンドウを動かすことはしない (--dry-run しか使わない)。
set -u
. "$(dirname "$0")/lib/assert.sh"

CMD="$CHEZMOI_SOURCE/private_dot_local/bin/executable_terminal-resize"

# --- 引数のパース ---
# ウィンドウの状態に依存しないので、GUI の無い環境でも同じ結果になる。
out=$(bash "$CMD" -h 2>&1)
code=$?
assert_eq "$code" "0" "-h が exit 0 で終わる"
assert_contains "$out" "Usage: terminal-resize" "-h が usage を出す"

for bad in 800 800x x600 0x600 -1x600 800X600 abcxdef; do
  bash "$CMD" -s "$bad" --dry-run >/dev/null 2>&1
  code=$?
  assert_eq "$code" "2" "不正なサイズで exit 2: $bad"
done

bash "$CMD" -s >/dev/null 2>&1
code=$?
assert_eq "$code" "2" "-s に値が無いと exit 2"

bash "$CMD" --nope >/dev/null 2>&1
code=$?
assert_eq "$code" "2" "不明なオプションで exit 2"

TERMINAL_RESIZE_BACKEND=nope bash "$CMD" --dry-run >/dev/null 2>&1
code=$?
assert_eq "$code" "2" "不明なバックエンドで exit 2"

# --- dry-run ---
# フォーカス中のウィンドウが取れない環境 (GUI 無し、権限無し) では
# dry-run が exit 1 で終わる。その場合はこの節を飛ばす。
bash "$CMD" --dry-run >/dev/null 2>&1
probe=$?
if [ "$probe" -eq 0 ]; then
  out=$(bash "$CMD" --dry-run 2>&1)
  assert_contains "$out" "size: 1024x768" "-s 省略で既定の 1024x768 になる"

  out=$(bash "$CMD" -s 800x600 --dry-run 2>&1)
  assert_contains "$out" "size: 800x600" "-s 800x600 が反映される"
  assert_contains "$out" "would run:" "dry-run が would run: 行を出す"

  # yabai がある環境では、dry-run がウィンドウを変えないことを frame で直接確かめる。
  if pgrep -x yabai >/dev/null 2>&1; then
    before=$(yabai -m query --windows --window | jq -c '.frame')
    bash "$CMD" -s 800x600 --dry-run >/dev/null 2>&1
    after=$(yabai -m query --windows --window | jq -c '.frame')
    assert_eq "$after" "$before" "dry-run がウィンドウの frame を変えない"

    out=$(TERMINAL_RESIZE_BACKEND=yabai bash "$CMD" -s 800x600 --dry-run 2>&1)
    assert_contains "$out" "backend: yabai" "yabai バックエンドを強制できる"
    assert_contains "$out" "abs:800:600" "yabai バックエンドが abs: の形で出す"

    # 中央座標は yabai が返す display frame から計算した期待値と突き合わせる。
    read -r dx dy dw dh < <(yabai -m query --displays --display |
      jq -r '"\(.frame.x | floor) \(.frame.y | floor) \(.frame.w | floor) \(.frame.h | floor)"')
    ex=$(( dx + (dw - 800) / 2 ))
    ey=$(( dy + (dh - 600) / 2 ))
    [ "$ex" -lt "$dx" ] && ex=$dx
    [ "$ey" -lt "$dy" ] && ey=$dy
    assert_contains "$out" "--move abs:$ex:$ey" "yabai バックエンドがディスプレイ中央の座標を出す"

    # ディスプレイより大きいサイズでは原点へ切り上げる。
    out=$(TERMINAL_RESIZE_BACKEND=yabai bash "$CMD" -s 99999x99999 --dry-run 2>&1)
    assert_contains "$out" "--move abs:$dx:$dy" "ディスプレイより大きいサイズで原点に切り上げる"
  fi

  # AppleScript バックエンドは yabai が動いていても強制すれば検証できる。
  TERMINAL_RESIZE_BACKEND=applescript bash "$CMD" -s 800x600 --dry-run >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    out=$(TERMINAL_RESIZE_BACKEND=applescript bash "$CMD" -s 800x600 --dry-run 2>&1)
    assert_contains "$out" "backend: applescript" "applescript バックエンドを強制できる"
    assert_contains "$out" "size: 800x600" "applescript バックエンドでもサイズが反映される"

    # 両バックエンドはフォーカス中のウィンドウがあるディスプレイを見る。
    # yabai がある環境では、その座標が一致することを直接確かめられる。
    if pgrep -x yabai >/dev/null 2>&1; then
      assert_contains "$out" "set position of front window to {$ex, $ey}" \
        "applescript バックエンドが yabai と同じ中央座標を出す"
    fi
  else
    printf '  アクセシビリティ権限が無いため applescript バックエンドのテストを飛ばした\n'
  fi
else
  printf '  フォーカス中のウィンドウが取れないため dry-run のテストを飛ばした\n'
fi

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
