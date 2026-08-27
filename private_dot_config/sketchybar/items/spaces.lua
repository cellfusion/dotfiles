local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local spaces = {}

for i = 1, 10, 1 do
	local space = sbar.add("space", "space." .. i, {
		space = i,
		icon = {
			font = { family = settings.font.numbers },
			string = i,
			padding_left = 8,
			padding_right = 6,
			color = colors.white,
			highlight_color = colors.red,
		},
		label = {
			padding_right = 10,
			color = colors.grey,
			highlight_color = colors.red,
			font = "sketchybar-app-font:Regular:16.0",
			y_offset = -1,
		},
		padding_right = 1,
		padding_left = 1,
		background = {
			color = colors.bg1,
			border_width = 0,
			height = 32,
		},
		popup = { background = { border_width = 5, border_color = colors.black } },
	})

	spaces[i] = space

	-- Bracket kept for grouping/padding; border removed (selection is shown by color)
	sbar.add("bracket", { space.name }, {
		background = {
			color = colors.transparent,
			height = 32,
			border_width = 0,
		},
	})

	-- Padding space
	sbar.add("space", "space.padding." .. i, {
		space = i,
		script = "",
		width = settings.group_paddings,
	})

	local space_popup = sbar.add("item", {
		position = "popup." .. space.name,
		padding_left = 5,
		padding_right = 0,
		background = {
			drawing = true,
			image = {
				corner_radius = 9,
				scale = 0.2,
			},
		},
	})

	space:subscribe("space_change", function(env)
		local selected = env.SELECTED == "true"
		space:set({
			icon = { highlight = selected },
			label = { highlight = selected },
		})
	end)

	space:subscribe("mouse.clicked", function(env)
		if env.BUTTON == "other" then
			space_popup:set({ background = { image = "space." .. env.SID } })
			space:set({ popup = { drawing = "toggle" } })
		else
			local op = (env.BUTTON == "right") and "--destroy" or "--focus"
			sbar.exec("yabai -m space " .. op .. " " .. env.SID)
		end
	end)

	space:subscribe("mouse.exited", function(_)
		space:set({ popup = { drawing = false } })
	end)
end

local space_window_observer = sbar.add("item", {
	drawing = false,
	updates = true,
})

space_window_observer:subscribe("space_windows_change", function(env)
	local icon_line = ""
	local no_app = true
	for app, count in pairs(env.INFO.apps) do
		no_app = false
		local lookup = app_icons[app]
		local icon = ((lookup == nil) and app_icons["Default"] or lookup)
		-- ウィンドウ数だけアイコンを繰り返す (2窓なら同じアイコンを2つ)
		for _ = 1, count do
			icon_line = icon_line .. icon
		end
	end

	if no_app then
		icon_line = " —"
	end
	sbar.animate("tanh", 10, function()
		spaces[env.INFO.space]:set({ label = icon_line })
	end)
end)
