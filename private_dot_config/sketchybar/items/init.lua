
-- Workspace management and the focused application are shown in the top bar.
-- The bottom bar is reserved for the media and status widgets.
-- require("items.apple")
-- require("items.menus")
-- require("items.spaces")
-- require("items.workspaces")
-- require("items.front_app")
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
-- Spotify は bottom bar の左側に置き、右クラスタとの衝突を避ける。
require("items.media")
