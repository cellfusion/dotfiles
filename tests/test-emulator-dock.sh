#!/usr/bin/env bash
# emulator-dock の引数パースと dry-run 出力を検証する。
# 実際にウィンドウを動かすことはしない (--dry-run しか使わない)。
# yabai は EMULATOR_DOCK_YABAI で差し替えたスタブに向ける。
set -u
. "$(dirname "$0")/lib/assert.sh"

CMD="$CHEZMOI_SOURCE/private_dot_config/yabai/executable_emulator-dock"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# --- yabai スタブ -------------------------------------------------------
# query には fixture を返し、config には固定値を返す。
# 受け取った引数は $STUB_LOG に積んで、変更系が呼ばれていないことを確かめる。
cat > "$tmpdir/yabai" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
case "$*" in
  "-m query --windows")  cat "$STUB_WINDOWS" ;;
  "-m query --spaces")   cat "$STUB_SPACES" ;;
  "-m query --displays") cat "$STUB_DISPLAYS" ;;
  "-m config window_gap")     printf '4\n' ;;
  "-m config top_padding")    printf '4\n' ;;
  "-m config bottom_padding") printf '38\n' ;;
  "-m config left_padding")   printf '4\n' ;;
  "-m config right_padding")  printf '4\n' ;;
  "-m config --space "*" right_padding")
    space=$(printf '%s' "$*" | sed -E 's/.*--space ([0-9]+).*/\1/')
    if [ "$space" = "${STUB_DOCKED_SPACE:-}" ]; then
      printf '%s\n' "${STUB_DOCKED_PADDING:-424}"
    else
      printf '4\n'
    fi
    ;;
  *) exit 0 ;;
esac
STUB
chmod +x "$tmpdir/yabai"

export STUB_LOG="$tmpdir/log"
export STUB_WINDOWS="$tmpdir/windows.json"
export STUB_SPACES="$tmpdir/spaces.json"
export STUB_DISPLAYS="$tmpdir/displays.json"
export EMULATOR_DOCK_YABAI="$tmpdir/yabai"

# display 1 は 2560x1440。space 4 に Ghostty / Chrome / emulator 本体 / ツールバー。
cat > "$STUB_DISPLAYS" <<'JSON'
[{"index":1,"frame":{"x":0.0,"y":0.0,"w":2560.0,"h":1440.0}},
 {"index":2,"frame":{"x":-1800.0,"y":597.0,"w":1800.0,"h":1169.0}}]
JSON

cat > "$STUB_SPACES" <<'JSON'
[{"index":1,"display":1},{"index":2,"display":1},{"index":3,"display":1},
 {"index":4,"display":1},{"index":5,"display":1},
 {"index":6,"display":2},{"index":7,"display":2},{"index":8,"display":2},{"index":9,"display":2}]
JSON

win_ghostty='{"id":314,"app":"Ghostty","subrole":"AXStandardWindow","space":4,"display":1,"is-floating":false,"frame":{"x":4.0,"y":35.0,"w":1274.0,"h":1367.0}}'
win_chrome='{"id":1038,"app":"Google Chrome","subrole":"AXStandardWindow","space":4,"display":1,"is-floating":false,"frame":{"x":1282.0,"y":35.0,"w":1274.0,"h":1367.0}}'
win_emu='{"id":37832,"app":"qemu-system-aarch64","subrole":"AXStandardWindow","space":4,"display":1,"is-floating":true,"frame":{"x":2140.0,"y":60.0,"w":351.0,"h":769.0}}'
win_bar='{"id":37833,"app":"qemu-system-aarch64","subrole":"AXDialog","space":4,"display":1,"is-floating":true,"frame":{"x":2491.0,"y":88.0,"w":61.0,"h":515.0}}'

write_windows() { printf '[%s]\n' "$(IFS=,; printf '%s' "$*")" > "$STUB_WINDOWS"; }

run_dock() { : > "$STUB_LOG"; bash "$CMD" "$@" 2>&1; }

# --- 引数のパース -------------------------------------------------------
write_windows "$win_ghostty" "$win_chrome" "$win_emu" "$win_bar"

out=$(bash "$CMD" -h 2>&1); code=$?
assert_eq "$code" "0" "-h が exit 0 で終わる"
assert_contains "$out" "Usage: emulator-dock" "-h が usage を出す"

bash "$CMD" --nope >/dev/null 2>&1
assert_eq "$?" "2" "不明なオプションで exit 2"

bash "$CMD" --closed >/dev/null 2>&1
assert_eq "$?" "2" "--closed に値が無いと exit 2"

bash "$CMD" --closed abc >/dev/null 2>&1
assert_eq "$?" "2" "--closed が数値でないと exit 2"

# --- emulator がいるとき ------------------------------------------------
# 予約幅 = 本体 351 + ツールバー 61 + gap 4 * 2 = 420
# 本体の x = 2560 - 4 - 61 - 351 = 2144
# 本体の y = 同じ space のタイル管理下ウィンドウの上端 35 に揃える
# would run: の行は EMULATOR_DOCK_YABAI のパスをそのまま出すので、引数だけを見る。
out=$(run_dock --dry-run)
assert_contains "$out" "emulator: id=37832 space=4 display=1" "本体ウィンドウを特定する"
assert_contains "$out" "reserve: 420" "本体とツールバーと隙間から予約幅を出す"
assert_contains "$out" "-m space 4 --padding abs:4:38:4:420" "emulator のいる space に空き地を作る"
assert_contains "$out" "-m window 37832 --move abs:2144:35" "本体を空き地へ寄せる"

log=$(cat "$STUB_LOG")
assert_not_contains "$log" "--padding" "dry-run が padding を実際に変えない"
assert_not_contains "$log" "--move" "dry-run がウィンドウを実際に動かさない"

# 他の space は既定のままなので触らない
assert_not_contains "$out" "-m space 1 --padding" "空き地の要らない space は触らない"
assert_not_contains "$out" "-m space 5 --padding" "空き地の要らない space は触らない"

# --- ツールバーが閉じているとき ----------------------------------------
# 予約幅 = 351 + 4 * 2 = 359 / x = 2560 - 4 - 351 = 2205
write_windows "$win_ghostty" "$win_chrome" "$win_emu"
out=$(run_dock --dry-run)
assert_contains "$out" "reserve: 359" "ツールバーが無ければその幅を足さない"
assert_contains "$out" "-m window 37832 --move abs:2205:35" "ツールバーが無い前提で寄せる"

# --- emulator がいないとき ----------------------------------------------
# space 4 に空き地が残っているので畳む
write_windows "$win_ghostty" "$win_chrome"
export STUB_DOCKED_SPACE=4 STUB_DOCKED_PADDING=420
out=$(run_dock --dry-run)
assert_contains "$out" "emulator: none" "emulator が無いと報告する"
assert_contains "$out" "-m space 4 --padding abs:4:38:4:4" "残った空き地を畳む"
unset STUB_DOCKED_SPACE STUB_DOCKED_PADDING

# 空き地が無ければ何も変えない
out=$(run_dock --dry-run)
assert_contains "$out" "emulator: none" "emulator が無いと報告する (空き地も無い)"
assert_not_contains "$out" "--padding" "畳むべき空き地が無ければ padding を触らない"

# --- --closed で消えたウィンドウを除外する ------------------------------
# window_destroyed は yabai の内部処理より先に発火するので、
# 消えたばかりのウィンドウがまだ query に残っていることがある。
write_windows "$win_ghostty" "$win_chrome" "$win_emu" "$win_bar"
export STUB_DOCKED_SPACE=4 STUB_DOCKED_PADDING=420
out=$(run_dock --closed 37832 --dry-run)
assert_contains "$out" "emulator: none" "--closed で指定した本体を無視する"
assert_contains "$out" "-m space 4 --padding abs:4:38:4:4" "本体が消えたら空き地を畳む"
unset STUB_DOCKED_SPACE STUB_DOCKED_PADDING

# 本体以外の id を渡しても本体は残る
out=$(run_dock --closed 37833 --dry-run)
assert_contains "$out" "emulator: id=37832" "ツールバーだけ閉じても本体は残る"
assert_contains "$out" "reserve: 359" "ツールバーが閉じたぶん予約幅が縮む"

printf 'SUMMARY %d %d\n' "$TESTS_RUN" "$TESTS_FAILED"
