// 直近のカレンダー予定を macOS の Calendar.sqlitedb から直接読む。
//
// EventKit の requestFullAccessToEvents は macOS 26 でバンドル化しても TCC
// プロンプトが発火せず使えなかったため、Full Disk Access を手動付与できる
// このバイナリで DB を直読みする方式に切り替えた。DB は読み取り専用・immutable
// で開く (CalendarAgent の WAL ロックを避けるため)。
//
// 出力: `YYYY-MM-DD HH:MM-HH:MM | 件名` を 1 行ずつ。
// 引数1 = 何日先まで取るか (既定 1 = 今日)。
//
// 制限: 時刻付き (all_day=0) の単発予定が対象。繰り返し予定は初回オカレンス
// しか行として存在しないため将来分は取りこぼす (RRULE 展開はしていない)。
import Foundation
import SQLite3

let CORE_DATA_EPOCH = 978_307_200.0 // 2001-01-01 00:00:00 UTC の unixtime

let days: Int = {
    if CommandLine.arguments.count > 1, let n = Int(CommandLine.arguments[1]), n > 0 {
        return n
    }
    return 1
}()

let dbPath = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"

// immutable=1 で WAL を無視した読み取り専用スナップショットとして開く
let uri = "file://" + dbPath + "?immutable=1"

var db: OpaquePointer?
let openFlags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
guard sqlite3_open_v2(uri, &db, openFlags, nil) == SQLITE_OK, db != nil else {
    // アクセス拒否 (Full Disk Access 未付与) もここに来る。無出力で終える。
    FileHandle.standardError.write(Data("Cannot open Calendar DB (grant Full Disk Access?)\n".utf8))
    exit(1)
}
defer { sqlite3_close(db) }

// 期間・書式・重複排除は SQL 側で完結させる。summary/start_date で GROUP BY し
// 複数カレンダーからの同一予定を畳む。
let sql = """
SELECT DISTINCT
  strftime('%Y-%m-%d %H:%M', start_date + \(Int(CORE_DATA_EPOCH)), 'unixepoch', 'localtime')
  || '-' || strftime('%H:%M', end_date + \(Int(CORE_DATA_EPOCH)), 'unixepoch', 'localtime')
  || ' | ' || summary
FROM CalendarItem
WHERE all_day = 0 AND summary IS NOT NULL
  AND (start_date + \(Int(CORE_DATA_EPOCH))) BETWEEN CAST(strftime('%s','now','-1 hour') AS INTEGER)
                                                 AND CAST(strftime('%s','now','+\(days) day') AS INTEGER)
GROUP BY summary, start_date
ORDER BY start_date;
"""

var stmt: OpaquePointer?
guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
    FileHandle.standardError.write(Data("Query prepare failed\n".utf8))
    exit(1)
}
defer { sqlite3_finalize(stmt) }

while sqlite3_step(stmt) == SQLITE_ROW {
    if let c = sqlite3_column_text(stmt, 0) {
        print(String(cString: c))
    }
}
