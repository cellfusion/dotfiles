local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Spotify のミニプレイヤー。bottom bar の中央に出す。
--
-- macOS 26 では MediaRemote が塞がれていて nowplaying-cli も SketchyBar 組み込みの
-- media_change / media.artwork も動かない。そのため情報は Spotify の AppleScript から
-- 取り、更新の検知は helpers/event_providers/spotify_events が送る spotify_change に頼る。
-- ポーリングはしていない。
--
-- display = 1 はメインディスプレイ (2560x1440, 原点 0,0)。ディスプレイ構成を変えると
-- 番号がずれるので、その場合はここを直す。
local DISPLAY = 1
local EVENT = "spotify_change"
local INFO = "$CONFIG_DIR/helpers/spotify_info.sh"
local PROVIDER = "$CONFIG_DIR/helpers/event_providers/spotify_events/bin/spotify_events"
local VOLUME_STEP = 5

-- カスタムイベントは subscribe より先に登録しておく必要がある
-- (items/workspaces.lua:15 と同じ)。プロバイダ側では登録しない。
sbar.add("event", EVENT)

sbar.exec("killall spotify_events >/dev/null; " .. PROVIDER .. " " .. EVENT)

-- Spotify アプリ内の音量。items/widgets/volume.lua が扱う macOS のシステム音量とは別物。
-- 初回の update() で実際の値に上書きされるので、ここでの 50 は仮の初期値。
local current_volume = 50
local muted_from = nil

local function osa(command)
	sbar.exec("osascript -e 'if application \"Spotify\" is running then tell application \"Spotify\" to " .. command .. "'")
end

local function volume_icon(v)
	if v <= 0 then
		return icons.volume._0
	elseif v < 20 then
		return icons.volume._10
	elseif v < 50 then
		return icons.volume._33
	elseif v < 80 then
		return icons.volume._66
	end
	return icons.volume._100
end

local cover = sbar.add("item", "spotify.cover", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	updates = true,
	padding_left = settings.paddings,
	padding_right = settings.paddings,
	icon = { drawing = false },
	label = { drawing = false },
	background = {
		-- Spotify のアートワークは実測 640x640。34px のバーに収めるため 0.04 (約 26px) にする。
		image = { scale = 0.04, corner_radius = 4 },
		color = colors.transparent,
		border_width = 0,
	},
})

-- title はアイテムレベル width = 0 で幅を占有しないため、artist と同じ x から
-- 描画され、y_offset で上下 2 行に見える。テキスト領域の幅は artist のアイテム
-- レベル width = 150 が予約する。label.align = "left" を効かせるには label.width
-- に領域幅 (150) を明示する必要がある。実幅のままでは中央寄せに見える。
local title = sbar.add("item", "spotify.title", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	width = 0,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = {
		font = { size = 11 },
		max_chars = 22,
		width = 150,
		align = "left",
		y_offset = 5,
	},
})

local artist = sbar.add("item", "spotify.artist", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	width = 150,
	padding_left = 0,
	padding_right = 0,
	icon = { drawing = false },
	label = {
		font = { size = 9 },
		color = colors.with_alpha(colors.white, 0.6),
		max_chars = 24,
		width = 150,
		align = "left",
		y_offset = -6,
	},
})

local prev = sbar.add("item", "spotify.prev", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	padding_left = settings.paddings,
	padding_right = settings.paddings,
	icon = { string = icons.media.back, font = { size = 13 } },
	label = { drawing = false },
})

local playpause = sbar.add("item", "spotify.playpause", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	padding_left = settings.paddings,
	padding_right = settings.paddings,
	icon = { string = icons.media.play_pause, font = { size = 15 } },
	label = { drawing = false },
})

local next_track = sbar.add("item", "spotify.next", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	padding_left = settings.paddings,
	padding_right = settings.paddings,
	icon = { string = icons.media.forward, font = { size = 13 } },
	label = { drawing = false },
})

local volume = sbar.add("item", "spotify.volume", {
	position = "center",
	display = DISPLAY,
	drawing = false,
	padding_left = settings.paddings,
	padding_right = settings.paddings,
	icon = { string = volume_icon(current_volume), font = { size = 13 } },
	label = { drawing = false },
})

local members = { cover, title, artist, prev, playpause, next_track, volume }

local bracket = sbar.add("bracket", "spotify.bracket", {
	cover.name,
	title.name,
	artist.name,
	prev.name,
	playpause.name,
	next_track.name,
	volume.name,
}, {
	display = DISPLAY,
	drawing = false,
	background = { color = colors.bg1, height = 30, corner_radius = 9 },
})

local function set_drawing(on)
	for _, item in ipairs(members) do
		item:set({ drawing = on })
	end
	bracket:set({ drawing = on })
end

local function update()
	sbar.exec(INFO, function(result)
		local line = (result or ""):match("[^\r\n]+")
		if not line then
			set_drawing(false)
			return
		end

		local fields = {}
		for field in (line .. "\t"):gmatch("([^\t]*)\t") do
			fields[#fields + 1] = field
		end

		local state, track, who, vol, art = fields[1], fields[2], fields[3], fields[4], fields[5]
		if state ~= "playing" and state ~= "paused" then
			set_drawing(false)
			return
		end

		current_volume = tonumber(vol) or current_volume

		-- 一時停止中は曲名を薄くして状態を示す。アイコンは playpause 固定。
		local alpha = (state == "playing") and 1.0 or 0.5
		title:set({ label = { string = track, color = colors.with_alpha(colors.white, alpha) } })
		artist:set({ label = { string = who, color = colors.with_alpha(colors.white, alpha * 0.6) } })
		volume:set({ icon = { string = volume_icon(current_volume) } })

		if art and art ~= "" then
			cover:set({ background = { image = { string = art, drawing = true } } })
		else
			-- キャッシュも無ければ前の曲のアートワークを出し続けない。
			cover:set({ background = { image = { drawing = false } } })
		end

		set_drawing(true)
	end)
end

cover:subscribe(EVENT, update)
cover:subscribe("forced", update)

prev:subscribe("mouse.clicked", function()
	osa("previous track")
end)

playpause:subscribe("mouse.clicked", function()
	osa("playpause")
end)

next_track:subscribe("mouse.clicked", function()
	osa("next track")
end)

volume:subscribe("mouse.scrolled", function(env)
	local delta = tonumber(env.SCROLL_DELTA) or 0
	if delta == 0 then
		return
	end
	local step = (delta > 0) and VOLUME_STEP or -VOLUME_STEP
	local v = math.max(0, math.min(100, current_volume + step))
	if v == current_volume then
		return
	end
	current_volume = v
	volume:set({ icon = { string = volume_icon(v) } })
	osa("set sound volume to " .. v)
end)

volume:subscribe("mouse.clicked", function()
	if current_volume > 0 then
		muted_from = current_volume
		current_volume = 0
	else
		current_volume = muted_from or 50
	end
	volume:set({ icon = { string = volume_icon(current_volume) } })
	osa("set sound volume to " .. current_volume)
end)

update()
