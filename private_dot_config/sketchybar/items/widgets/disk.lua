local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Execute the event provider binary which provides the event "disk_update" for
-- the disk load data, which is fired every 30.0 seconds.
sbar.exec("killall disk_load >/dev/null; $CONFIG_DIR/helpers/event_providers/disk_load/bin/disk_load disk_update 30.0")

local disk = sbar.add("item", "widgets.disk", {
	position = "right",
	background = {
		height = 22,
		color = { alpha = 0 },
		border_color = { alpha = 0 },
		drawing = true,
	},
	icon = { string = icons.disk },
	label = {
		string = "??G",
		font = { family = settings.font.numbers },
	},
	padding_right = settings.paddings,
})

disk:subscribe("disk_update", function(env)
	local usage = tonumber(env.usage_percent)
	local used = env.used_gb
	local total = env.total_gb

	local color = colors.green
	if usage > 80 then
		if usage < 90 then
			color = colors.orange
		else
			color = colors.red
		end
	end

	disk:set({
		icon = { color = color },
		label = {
			string = used .. "G/" .. total .. "G",
			color = color,
		},
	})
end)

disk:subscribe("mouse.clicked", function(env)
	sbar.exec("open ~")
end)

-- Background around the disk item
sbar.add("bracket", "widgets.disk.bracket", { disk.name }, {
	background = {
		color = colors.bg1,
		height = 32,
	},
})

-- Padding for the disk item
sbar.add("item", "widgets.disk.padding", {
	position = "right",
	width = settings.group_paddings,
})
