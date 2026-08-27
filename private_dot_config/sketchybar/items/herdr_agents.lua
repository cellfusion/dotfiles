local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

-- herdr の全 running セッションを走査し、確認待ち(done)/入力待ち(blocked) の
-- エージェント数をセッション別に表示する。herdr CLI に push イベントは無いので
-- Slack バッジ (notifications.lua) と同じくポーリング (update_freq) で拾う。
-- 集計は helpers/herdr_agents.sh が "<severity>\t<label>" を返す。
local herdr = sbar.add("item", "widgets.herdr", {
	position = "right",
	icon = {
		string = app_icons["Ghostty"],
		font = "sketchybar-app-font:Regular:16.0",
		color = colors.grey,
		padding_left = 8,
		padding_right = 8,
	},
	label = {
		drawing = false,
		string = "",
		font = { family = settings.font.text, style = settings.font.style_map["Semibold"] },
		padding_left = 4,
		padding_right = 0,
	},
	update_freq = 5,
	-- クリックでターミナル (herdr の母艦) を前面へ。
	click_script = "open -a Ghostty",
})

sbar.add("bracket", "widgets.herdr.bracket", { herdr.name }, {
	background = { color = colors.bg1, height = 32 },
})

sbar.add("item", "widgets.herdr.padding", {
	position = "right",
	width = settings.group_paddings,
})

local function update()
	sbar.exec("$CONFIG_DIR/helpers/herdr_agents.sh", function(result)
		local sev, label = (result or ""):match("^(%S*)\t(.*)$")
		label = (label or ""):gsub("%s+$", "")
		if not sev or sev == "none" or label == "" then
			-- 要対応なし: アイコンだけ非アクティブ色で残す
			herdr:set({ icon = { color = colors.grey }, label = { drawing = false } })
		else
			local color = (sev == "blocked") and colors.red or colors.yellow
			herdr:set({
				icon = { color = color },
				label = { drawing = true, string = label, color = color },
			})
		end
	end)
end

herdr:subscribe({ "forced", "routine", "system_woke" }, update)
