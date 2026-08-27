local colors = require("colors")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

sbar.add("item",{ width = 4 })

local function lines(str)
	local result = {}
	for line in str:gmatch("[^\n]+") do
		table.insert(result, line)
	end
	return result
end

sbar.add("event", "aerospace_workspace_change")

local spaces = {}

local function set_icon_line(workspace_id, appNames, currentAppName)
	local appCounts = {}
	-- Split the input string by newline into individual app names
	for appName in string.gmatch(appNames, "[^\r\n]+") do
		-- Trim leading and trailing whitespace
		appName = appName:match("^%s*(.-)%s*$")
		if appCounts[appName] then
			appCounts[appName] = appCounts[appName] + 1
		else
			appCounts[appName] = 1
		end
	end

	local icon_line = ""
	for app, _ in pairs(appCounts) do
		local lookup = app_icons[app]
		local icon = ((lookup == nil) and app_icons["Default"] or lookup)
		icon_line = icon_line .. icon
	end

	if icon_line == "" then
		spaces[workspace_id]:set({ label = "-", drawing = false })
	else
		spaces[workspace_id]:set({
			label = icon_line,
			drawing = true,
		})
	end
end

local function set_active_workspace(workspace_id)
	for id, space in pairs(spaces) do
		if id == workspace_id then
			space:set({
				icon = { color = colors.purple },
				label = { color = colors.purple },
				background = { color = colors.with_alpha(colors.purple, 0.4) },
			})
		else
			space:set({
				icon = { color = colors.grey },
				label = { color = colors.grey },
				background = { color = colors.with_alpha(colors.bg2, 0.5) },
			})
		end
	end
end

-- Initialize workspaces
local function initialize_workspaces()
	sbar.exec(
		"aerospace list-workspaces --all --format '%{workspace}|%{monitor-appkit-nsscreen-screens-id}'",
		function(all_workspaces)
			local aerospaces = lines(all_workspaces)

			for i, value in pairs(aerospaces) do
				local sid, mid = value:match("^(.-)|(.+)$")
				local space_name = "space." .. sid
				local space_label = sid
				local space = sbar.add("item", space_name, {
					space = mid,
					display = mid,
					drawing = true,
					icon = {
						color = colors.grey,
						font = { family = settings.font.numbers },
						string = space_label,
						padding_left = 6,
						padding_right = 4,
						highlight_color = colors.red,
					},
					label = {
						padding_right = 4,
						color = colors.grey,
						highlight_color = colors.white,
						font = "sketchybar-app-font:Regular:16.0",
					},
					padding_right = 4,
					padding_left = 0,
					background = {
						color = colors.with_alpha(colors.bg2, 0.5),
						border_width = 0,
						height = 24,
						corner_radius = 4,
					},
				})
				if sid ~= nil then
					spaces[sid] = space
				end

				space:subscribe("mouse.clicked", function(env)
					sbar.exec("aerospace workspace " .. sid)
				end)
			end
		end
	)
end
initialize_workspaces()

local space_observer = sbar.add("item", {
	drawing = false,
	updates = true,
})

local function update_icons(currentAppName)
	sbar.exec("aerospace list-windows --all --format '%{app-name}|%{workspace}'", function(all_windows)
		local workspace_apps = {}
		for line in string.gmatch(all_windows, "[^\r\n]+") do
			local appName, workspaceID = line:match("^(.-)|(.+)$")
			if workspace_apps[workspaceID] == nil then
				workspace_apps[workspaceID] = ""
			end
			workspace_apps[workspaceID] = workspace_apps[workspaceID] .. appName .. "\n"
		end

		-- workspace_appsに存在しないworkspaceIDも初期化しておく
		for workspaceID, _ in pairs(spaces) do
			if workspace_apps[workspaceID] == nil then
				workspace_apps[workspaceID] = ""
			end
		end

		for workspaceID, apps in pairs(workspace_apps) do
			set_icon_line(workspaceID, apps, currentAppName)
		end
	end)
end

-- Update workspace icons on change
space_observer:subscribe("aerospace_workspace_change", function(env)
	set_active_workspace(env.FOCUSED_WORKSPACE)
end)

space_observer:subscribe("front_app_switched", function(env)
	update_icons(env.INFO)
end)

-- sbar.add("bracket", { "/space\\..*/" }, {
-- 	background = { color = colors.bg1 },
-- })

sbar.exec("aerospace list-workspaces --focused", function(workspace)
	sbar.trigger("aerospace_workspace_change", { FOCUSED_WORKSPACE = workspace })
end)
