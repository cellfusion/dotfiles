local colors = require("colors")

-- Equivalent to the --bar domain
sbar.bar({
	height = 34,
	color = colors.transparent,
	corner_radius = 0,
	border_color = colors.black,
	border_width = 0,
	y_offset = 0,
	margin = 0,
	position = "bottom", -- left, right, top, bottom
	padding_right = 4,
	padding_left = 4,
})
