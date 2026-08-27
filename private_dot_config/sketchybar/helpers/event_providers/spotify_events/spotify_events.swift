// Spotify の再生状態が変わったら SketchyBar のカスタムイベントを発火する常駐プロセス。
//
// 使い方: spotify_events [event_name]   (既定 spotify_change)
//
// PlaybackStateChanged だけでは Spotify の終了を検知できない (終了時に通知が
// 飛ばない) ため、NSWorkspace の起動 / 終了通知もあわせて購読する。
//
// 通知の userInfo には曲名なども入っているが使わない。キー名は Spotify の
// バージョンで変わりうるので、通知は「状態が変わった」という合図としてのみ
// 扱い、値は Lua 側が AppleScript から取り直す。
import AppKit
import Foundation

let eventName = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "spotify_change"
let spotifyBundleID = "com.spotify.client"

// Homebrew の既定パスを先に見て、無ければ PATH から探す。
let sketchybarPath: String = {
    let preferred = "/opt/homebrew/bin/sketchybar"
    if FileManager.default.isExecutableFile(atPath: preferred) {
        return preferred
    }
    return "/usr/bin/env"
}()

// Spotify は 1 回の操作で通知を複数回送ることがあるので、まとめて 1 回に潰す。
var pending: DispatchWorkItem?

func trigger() {
    pending?.cancel()
    let work = DispatchWorkItem {
        let p = Process()
        if sketchybarPath == "/usr/bin/env" {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["sketchybar", "--trigger", eventName]
        } else {
            p.executableURL = URL(fileURLWithPath: sketchybarPath)
            p.arguments = ["--trigger", eventName]
        }
        do {
            try p.run()
            FileHandle.standardError.write(Data("trigger \(eventName)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("failed to run \(sketchybarPath): \(error)\n".utf8))
        }
    }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
}

// 再生・一時停止・曲の切り替え
DistributedNotificationCenter.default().addObserver(
    forName: NSNotification.Name("com.spotify.client.PlaybackStateChanged"),
    object: nil,
    queue: .main
) { _ in
    trigger()
}

// Spotify 自体の起動と終了
for name in [
    NSWorkspace.didLaunchApplicationNotification,
    NSWorkspace.didTerminateApplicationNotification,
] {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: name,
        object: nil,
        queue: .main
    ) { note in
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        guard app?.bundleIdentifier == spotifyBundleID else { return }
        trigger()
    }
}

// 起動直後の状態を 1 回反映させる
trigger()

RunLoop.main.run()
