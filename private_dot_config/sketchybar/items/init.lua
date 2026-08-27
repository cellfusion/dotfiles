
--require("items.apple")
-- require("items.menus")
-- ウィンドウマネージャに合わせてどちらか一方を有効にする
-- spaces     : yabai (macOS ネイティブスペース連動)
-- workspaces : aerospace
require("items.spaces")
-- require("items.workspaces")
-- require("items.front_app")
-- 日付(時計) と IME は macOS メニューバーに出るため非表示
-- require("items.calendar")
-- require("items.ime")
require("items.widgets")
require("items.notifications")
-- herdr の各セッションの done/blocked エージェント数 (Slack notification の左)
require("items.herdr_agents")
-- 3アカウント分の週次リミット使用率
require("items.usage")
-- 予定表示は Slack notification の左に置く (right クラスタは後に require するほど左)
require("items.calendar_events")
-- Spotify のミニプレイヤー (bar 中央)
require("items.media")
