local colors = require("colors")

-- The top bar is a separate SketchyBar instance so the bottom media/status bar
-- can keep its own center and right clusters.
sbar.bar({
	height = 34,
	color = colors.transparent,
	corner_radius = 0,
	border_color = colors.black,
	border_width = 0,
	y_offset = 0,
	margin = 0,
	position = "top",
	-- Keep the custom top bar visible above the native menu bar and app windows.
	topmost = "window",
	padding_right = 4,
	padding_left = 4,
})
