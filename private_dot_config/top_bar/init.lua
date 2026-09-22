sbar = require("sketchybar")
sbar.set_bar_name("top_bar")

sbar.begin_config()
require("bar")
require("default")
require("items")
sbar.end_config()

sbar.event_loop()
