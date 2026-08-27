# Spotify の distributed notification を購読して SketchyBar のイベントを発火する
# 常駐プロセス。TCC 権限は不要なので ad-hoc 署名はしない。
bin/spotify_events: spotify_events.swift | bin
	swiftc spotify_events.swift -o bin/spotify_events

bin:
	mkdir -p bin
