#!/bin/bash
# Spotify の再生情報を 1 行のタブ区切りで出力する。
#   <state>\t<title>\t<artist>\t<volume>\t<artwork_path>
# state は playing / paused / stopped。未起動時は stopped を返す。
#
# macOS 26 では MediaRemote が塞がれていて nowplaying-cli が使えないため、
# Spotify の AppleScript を情報源にしている。
#
# `application "Spotify" is running` のガードは必須。これを外して
# `tell application "Spotify"` を直接書くと、未起動時に Spotify が起動する。
#
# AppleScript 変数名を `st` にすると、この環境（ja_JP ロケール）では
# 予約語と衝突して syntax error になる（`osascript 2>/dev/null` で握り
# 潰され、常に stopped にフォールバックしてしまう）。`playerSt` を使うこと。

set -uo pipefail

CACHE_DIR="$HOME/.cache/sketchybar/spotify"
ART_PATH="$CACHE_DIR/artwork.jpg"
ART_URL_PATH="$CACHE_DIR/artwork.url"

fallback() {
	printf 'stopped\t\t\t0\t\n'
	exit 0
}

info="$(osascript 2>/dev/null <<'APPLESCRIPT'
if application "Spotify" is running then
	tell application "Spotify"
		set playerSt to player state as text
		set v to sound volume as text
		if playerSt is "stopped" then
			return "stopped" & tab & "" & tab & "" & tab & v & tab & ""
		end if
		return playerSt & tab & (name of current track) & tab & (artist of current track) & tab & v & tab & (artwork url of current track)
	end tell
else
	return "stopped" & tab & "" & tab & "" & tab & "0" & tab & ""
end if
APPLESCRIPT
)"

[ -z "$info" ] && fallback

IFS=$'\t' read -r state title artist volume url <<<"$info"
[ -z "${state:-}" ] && fallback

# AppleScript の `&` は missing value をリテラル文字列 "missing value" に落とす
# (`osascript -e 'return "a" & tab & (missing value)'` で確認済み)。放置すると
# 毎回 "missing value" 相手に curl が失敗し続け、かつアートワークの無い曲でも
# 前回のキャッシュ画像が表示され続けてしまうため、ここで空文字に正規化する。
[ "${url:-}" = "missing value" ] && url=""

# アートワークは URL が変わったときだけ取り直す。同じ曲を再生し続けている間は
# ネットワークに出ない。取得に失敗したら前回のファイルをそのまま使う。
art=""
if [ -n "${url:-}" ]; then
	mkdir -p "$CACHE_DIR"
	if [ ! -f "$ART_PATH" ] || [ "$url" != "$(cat "$ART_URL_PATH" 2>/dev/null)" ]; then
		if curl --max-time 5 -sfL "$url" -o "$ART_PATH.tmp"; then
			mv -f "$ART_PATH.tmp" "$ART_PATH"
			printf '%s' "$url" >"$ART_URL_PATH"
		else
			rm -f "$ART_PATH.tmp"
		fi
	fi
	[ -f "$ART_PATH" ] && art="$ART_PATH"
fi

printf '%s\t%s\t%s\t%s\t%s\n' "$state" "$title" "$artist" "${volume:-0}" "$art"
