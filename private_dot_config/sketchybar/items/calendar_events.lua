local colors = require("colors")
local settings = require("settings")
local icons = require("icons")

-- 直近のカレンダー予定を EventKit バイナリ (helpers/event_providers/calendar_events)
-- から取得して表示する。
--   平時          : カレンダーアイコンのみ
--   予定が近い    : アイコン + 件名 + 「in Xm」。URGENT 以内は赤で強調
--   クリック      : 直近の予定一覧を popup 表示
-- バイナリ出力は `YYYY-MM-DD HH:MM-HH:MM | 件名`。診断行は正規表現で弾く。
local BIN = "$CONFIG_DIR/helpers/event_providers/calendar_events/bin/calendar_events"
local DAYS = 2 -- popup 用に翌日ぶんまで取る
local THRESHOLD = 15 -- 分: これ以内なら件名を inline 表示
local URGENT = 5 -- 分: これ以内は赤で強調
local MAX_ROWS = 6 -- popup に並べる最大件数
local POPUP_WIDTH = 240

local cal = sbar.add("item", "widgets.calevents", {
	position = "right",
	icon = {
		string = icons.calendar,
		color = colors.white,
		padding_left = 8,
		padding_right = 6,
		font = { style = settings.font.style_map["Regular"], size = 15.0 },
	},
	label = {
		drawing = false,
		color = colors.white,
		max_chars = 22,
		padding_right = 8,
		font = { size = 12.0 },
	},
	update_freq = 30,
	popup = { align = "left" },
})

sbar.add("bracket", "widgets.calevents.bracket", { cal.name }, {
	background = { color = colors.bg1, height = 32 },
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

-- ---------------------------------------------------------------- popup ----

sbar.add("item", "widgets.calevents.header", {
	position = "popup." .. cal.name,
	icon = { drawing = false },
	label = {
		string = "直近の予定",
		color = colors.grey,
		align = "left",
		font = { style = settings.font.style_map["Bold"], size = 11.0 },
	},
	width = POPUP_WIDTH,
})

local rows = {}
for i = 1, MAX_ROWS do
	rows[i] = sbar.add("item", "widgets.calevents.row." .. i, {
		position = "popup." .. cal.name,
		drawing = false,
		icon = { drawing = false },
		label = { string = "", color = colors.white, align = "left", max_chars = 30, font = { size = 12.0 } },
		width = POPUP_WIDTH,
	})
end

local empty_row = sbar.add("item", "widgets.calevents.empty", {
	position = "popup." .. cal.name,
	drawing = false,
	icon = { drawing = false },
	label = { string = "予定なし", color = colors.grey, align = "left", font = { size = 12.0 } },
	width = POPUP_WIDTH,
})

-- ---------------------------------------------------------------- update ---

local function parse(line)
	local y, mo, d, h, mi, _, _, title = line:match("^(%d+)-(%d+)-(%d+) (%d+):(%d+)-(%d+):(%d+) | (.+)$")
	if not y then
		return nil
	end
	local start = os.time({
		year = tonumber(y),
		month = tonumber(mo),
		day = tonumber(d),
		hour = tonumber(h),
		min = tonumber(mi),
		sec = 0,
	})
	return { start = start, hm = h .. ":" .. mi, title = title }
end

local function update()
	sbar.exec(BIN .. " " .. DAYS, function(result)
		local now = os.time()
		local events = {}
		for line in (result or ""):gmatch("[^\n]+") do
			local e = parse(line)
			-- 進行中 (1h 前開始まで) と未来の予定だけ残す
			if e and e.start > now - 3600 then
				events[#events + 1] = e
			end
		end
		table.sort(events, function(a, b)
			return a.start < b.start
		end)

		-- popup 行の更新
		for i = 1, MAX_ROWS do
			local e = events[i]
			if e then
				rows[i]:set({ drawing = true, label = e.hm .. "  " .. e.title })
			else
				rows[i]:set({ drawing = false })
			end
		end
		empty_row:set({ drawing = (#events == 0) })

		-- inline 表示: 次の予定までの分
		local next_event = events[1]
		if not next_event then
			cal:set({ icon = { color = colors.white }, label = { drawing = false } })
			return
		end

		local mins = math.floor((next_event.start - now) / 60)
		if mins <= THRESHOLD then
			local color = (mins <= URGENT) and colors.red or colors.yellow
			local when = (mins <= 0) and "now" or ("in " .. mins .. "m")
			cal:set({
				icon = { color = color },
				label = { drawing = true, color = color, string = next_event.title .. "  " .. when },
			})
		else
			cal:set({ icon = { color = colors.white }, label = { drawing = false } })
		end
	end)
end

cal:subscribe({ "forced", "routine", "system_woke" }, update)

cal:subscribe("mouse.clicked", function()
	update()
	cal:set({ popup = { drawing = "toggle" } })
end)

cal:subscribe("mouse.exited", function()
	cal:set({ popup = { drawing = false } })
end)
