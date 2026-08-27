# Calendar.sqlitedb を直読みする単体バイナリ。EventKit は使わないので TCC
# プロンプトは不要。代わりに Full Disk Access をこのバイナリに手動付与する
# (システム設定 → プライバシーとセキュリティ → フルディスクアクセス → +)。
# ad-hoc 署名で安定した識別子を与え、FDA 付与が再ビルドまで保持されるようにする。
bin/calendar_events: calendar_events.swift | bin
	swiftc calendar_events.swift -o bin/calendar_events -lsqlite3
	codesign --force --sign - --identifier com.cellfusion.sketchybar.calendar-events bin/calendar_events

bin:
	mkdir -p bin
