local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

local apple = sbar.add("item", {
	icon = {
		font = { size = 16.0 },
		string = icons.apple,
		padding_right = 11,
		padding_left = 11,
	},
	label = { drawing = false },
})

-- Padding item required because of bracket
sbar.add("item", { width = 4 })
