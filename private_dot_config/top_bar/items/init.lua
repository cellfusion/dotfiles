-- Left cluster: focused application followed by the yabai workspace switcher.
require("items.front_app")
require("items.spaces")

-- Right items are added from the outside in. The resulting order is:
-- Volume, Battery, WiFi, IME, Date/Time.
require("items.calendar")
require("items.ime")
require("items.widgets.wifi")
require("items.widgets.battery")
require("items.widgets.volume")
