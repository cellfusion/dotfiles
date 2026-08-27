return {
	black = 0xff16121b,
	white = 0xffc0caf5, -- tokyonight FOREGROUND
	red = 0xfff7768e,
	green = 0xff9ece6a,
	blue = 0xff7aa2f7, -- tokyonight BLUE
	yellow = 0xffe0af68,
	orange = 0xfff5a97f,
	magenta = 0xffbb9af7,
	grey = 0xff565f89, -- tokyonight COMMENT
	purple = 0xff9d7cd8,
	pink = 0xffbb9af7,
	cyan = 0xff7dcfff,
	transparent = 0x00000000,

	bar = {
		bg = 0xcc1a1f2b,
		border = 0xff223046, -- tokyonight CURRENT_LINE
	},
	popup = {
		bg = 0xcc1a1f2b,
		border = 0xff565f89, -- tokyonight COMMENT
	},
	bg1 = 0xcc1a1f2b,
	bg2 = 0xff223046, -- tokyonight CURRENT_LINE

	with_alpha = function(color, alpha)
		if alpha > 1.0 or alpha < 0.0 then
			return color
		end
		return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
	end,
}

-- # TokyoNight Colors
-- BACKGROUND="0xff1a1f2b"
-- BACKGROUND_TRANSPARENT="0xcc1a1f2b"
-- CURRENT_LINE="0xff223046"
-- FOREGROUND="0xffc0caf5"
-- COMMENT="0xff565f89"
-- CYAN="0xff7dcfff"
-- GREEN="0xff9ece6a"
-- ORANGE="0xfff5a97f"
-- PINK="0xffbb9af7"
-- PURPLE="0xff9d7cd8"
-- RED="0xfff7768e"
-- YELLOW="0xffe0af68"
-- TRANSPARENT="0x00000000"
-- BLACK="0xff16121b"
