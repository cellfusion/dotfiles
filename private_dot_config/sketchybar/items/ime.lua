local settings = require("settings")
local colors = require("colors")

-- 入力ソース変更は NSDistributedNotification で飛んでくるので、それを
-- sketchybar のイベントとして登録する (画面収録権限は不要)
sbar.add("event", "input_change", "AppleSelectedInputSourcesChangedNotification")

-- "Input Mode" (IME 内部モード) と "Bundle ID" (キーボードレイアウト) の
-- どちらで来ても表示できるようにマップを分けておく
local mode_map = {
	["com.apple.inputmethod.Roman"] = { label = "A", color = colors.grey },
	["com.apple.inputmethod.Japanese"] = { label = "あ", color = colors.cyan },
	["com.apple.inputmethod.Japanese.Hiragana"] = { label = "あ", color = colors.cyan },
	["com.apple.inputmethod.Japanese.Katakana"] = { label = "ア", color = colors.cyan },
	["com.apple.inputmethod.Japanese.HalfWidthKana"] = { label = "ｱ", color = colors.cyan },
	["com.apple.inputmethod.Japanese.FullWidthRoman"] = { label = "Ａ", color = colors.cyan },
}

local bundle_map = {
	["com.apple.keylayout.ABC"] = { label = "A", color = colors.grey },
	["com.apple.keylayout.US"] = { label = "A", color = colors.grey },
	["com.google.inputmethod.Japanese"] = { label = "あ", color = colors.cyan },
	["jp.sourceforge.inputmethod.aquaskk"] = { label = "SKK", color = colors.green },
}

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local ime = sbar.add("item", "widgets.ime", {
	position = "right",
	icon = { drawing = false },
	label = {
		string = "?",
		color = colors.white,
		padding_left = 4,
		padding_right = 4,
		width = "dynamic",
		align = "center",
		font = {
			style = settings.font.style_map["Bold"],
			size = 13.0,
		},
	},
	padding_left = 2,
	padding_right = 2,
	click_script = "open '/System/Library/PreferencePanes/Keyboard.prefPane'",
})

sbar.add("bracket", "widgets.ime.bracket", { ime.name }, {
	background = { color = colors.bg1, height = 32 },
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local function update()
	-- plist をそのまま読むと構造が深いので、必要な行だけ拾う
	sbar.exec("defaults read com.apple.HIToolbox AppleSelectedInputSources", function(result)
		if not result then
			return
		end

		local mode = result:match('"Input Mode"%s*=%s*"([^"]+)"')
		local bundle = result:match('"Bundle ID"%s*=%s*"([^"]+)"')

		local entry = (mode and mode_map[mode]) or (bundle and bundle_map[bundle])
		if not entry then
			-- 未知の入力ソースは末尾の識別子だけ出しておく (設定漏れに気付ける)
			local fallback = mode or bundle or "?"
			entry = { label = fallback:match("([^%.]+)$") or "?", color = colors.white }
		end

		ime:set({ label = { string = entry.label, color = entry.color } })
	end)
end

ime:subscribe({ "forced", "input_change" }, update)
