local colors = require("colors")
local settings = require("settings")

local front_app = sbar.add("item", "front_app", {
	display = "active",
	icon = { drawing = false },
	label = {
		max_chars = 24,
		font = {
			style = settings.font.style_map["Black"],
			size = 12.0,
		},
	},
	updates = true,
})

local function set_front_app(app_name)
	if app_name and app_name ~= "" then
		front_app:set({ label = { string = app_name } })
	end
end

front_app:subscribe("front_app_switched", function(env)
	set_front_app(env.INFO)
end)

-- front_app_switched may not fire for the application that was already focused
-- when the bar starts, so seed the label from yabai once at startup.
sbar.exec("yabai -m query --windows --window 2>/dev/null | jq -r '.app // empty'", function(result)
	set_front_app((result or ""):match("[^\r\n]+"))
end)

-- front_app:subscribe("mouse.clicked", function(env)
-- 	sbar.trigger("swap_menus_and_spaces")
-- end)
