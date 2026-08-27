local icons = require("icons")
local colors = require("colors")
local settings = require("settings")

-- Execute the event provider binary which provides the event "memory_update" for
-- the memory load data, which is fired every 2.0 seconds.
sbar.exec("killall memory_load >/dev/null; $CONFIG_DIR/helpers/event_providers/memory_load/bin/memory_load memory_update 2.0")

local memory = sbar.add("item", "widgets.memory", {
	position = "right",
	icon = { string = icons.memory },
	label = {
		string = "??%",
		font = { family = settings.font.numbers },
	},
	padding_right = settings.paddings,
})

memory:subscribe("memory_update", function(env)
	local usage = tonumber(env.usage_percent)

	local color = colors.blue
	if usage > 30 then
		if usage < 60 then
			color = colors.yellow
		elseif usage < 80 then
			color = colors.orange
		else
			color = colors.red
		end
	end

	memory:set({
		icon = { color = color },
		label = { string = env.usage_percent .. "%", color = color },
	})
end)

memory:subscribe("mouse.clicked", function(env)
	sbar.exec("open -a 'Activity Monitor'")
end)

-- Background around the memory item
sbar.add("bracket", "widgets.memory.bracket", { memory.name }, {
	background = {
		color = colors.bg1,
		height = 32,
	},
})

-- Padding for the memory item
sbar.add("item", "widgets.memory.padding", {
	position = "right",
	width = settings.group_paddings,
})
