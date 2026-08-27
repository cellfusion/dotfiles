local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

-- Slack の Dock バッジ (未読メンション / DM 数) を lsappinfo から拾う。
-- 数字バッジがあるときだけ表示し、無ければ item ごと隠す (通知の見落とし対策)。
-- lsappinfo は特別な権限不要。バッジ変化のイベントは無いのでポーリングで拾う。
local WATCH = "Slack"

-- 通知が無いときはアイコンを非アクティブ色 (grey) で常時表示。
-- 未読があるときはアイコンの色を赤に変えるだけ (件数バッジは出さない)。
local slack = sbar.add("item", "widgets.slack", {
	position = "right",
	icon = {
		string = app_icons[WATCH],
		font = "sketchybar-app-font:Regular:16.0",
		color = colors.grey,
		padding_left = 8,
		padding_right = 8,
	},
	update_freq = 5,
	click_script = "open -a Slack",
})

sbar.add("bracket", "widgets.slack.bracket", { slack.name }, {
	background = { color = colors.bg1, height = 32 },
})

sbar.add("item", "widgets.slack.padding", {
	position = "right",
	width = settings.group_paddings,
})

local function update()
	-- StatusLabel は `"StatusLabel"={ "label"="5" }` の形。数字部分だけ取り出す。
	local cmd = [[lsappinfo -all info -only StatusLabel "]]
		.. WATCH
		.. [[" 2>/dev/null | sed -nr 's/.*"label"="(.+)".*/\1/p']]
	sbar.exec(cmd, function(result)
		local badge = (result or ""):gsub("%s+", "")
		-- 未読の有無でアイコンの色だけ切り替える (grey ⇄ red)
		slack:set({ icon = { color = (badge == "") and colors.grey or colors.red } })
	end)
end

slack:subscribe({ "forced", "routine", "front_app_switched", "system_woke" }, update)
