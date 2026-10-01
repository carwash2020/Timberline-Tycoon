--!nocheck
-- UITheme (StarterPlayerScripts/UITheme): the left column follows Roblox's
-- chat window, and a chat property that can't be read never stops it;
-- WatchLeftColumn (the toasts keep clear of the column); the colours other
-- code relies on.
return function(t)
	local roblox = t.roblox
	local Instance, Vector2 = roblox.Instance, roblox.Vector2

	-- A UITheme on a desktop (no touch, a keyboard, no camera yet: 1x),
	-- with these TextChatService configs ([className] = config).
	local function theme(configs)
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local loader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
				},
				Players = {
					LocalPlayer = {
						WaitForChild = function()
							return playerGui
						end,
					},
				},
				TextChatService = {
					FindFirstChildOfClass = function(_, className)
						return configs[className]
					end,
				},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			},
			globals = {
				workspace = { CurrentCamera = nil },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
				},
			},
		})
		return loader:load("StarterPlayer/StarterPlayerScripts/UITheme"), playerGui
	end

	-- A chat config whose Enabled reads `enabled` and whose box properties
	-- error, as a property this client doesn't have would.
	local function unreadable(enabled)
		return setmetatable({}, {
			__index = function(_, key)
				if key == "Enabled" then
					return enabled
				end
				error(tostring(key) .. " is not a valid member of ChatWindowConfiguration")
			end,
		})
	end

	-- Puts something in the left column; returns the column's position.
	local function columnAt(configs)
		local UITheme, playerGui = theme(configs)
		UITheme.LeftColumn(Instance.new("Frame"), 1)
		local column = playerGui:FindFirstChild("LeftColumn"):FindFirstChild("Column")
		local p = column.Position
		local function round(x) -- UDim scales are 32-bit floats
			return math.floor(x * 1000 + 0.5) / 1000
		end
		return { round(p.X.Scale), p.X.Offset, round(p.Y.Scale), p.Y.Offset }
	end

	t.test("the column sits 10 under the chat window", function()
		local window = { Enabled = true, AbsolutePosition = Vector2.new(8, 20), AbsoluteSize = Vector2.new(300, 200) }
		local bar = { Enabled = true, AbsolutePosition = Vector2.new(8, 224), AbsoluteSize = Vector2.new(300, 36) }
		t.eq(columnAt({ ChatWindowConfiguration = window }), { 0, 12, 0, 230 })
		t.eq(columnAt({ ChatWindowConfiguration = window, ChatInputBarConfiguration = bar }), { 0, 12, 0, 270 })
	end)

	t.test("no chat, or chat turned off: 30% down the screen", function()
		t.eq(columnAt({}), { 0, 12, 0.3, 0 })
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(false) }), { 0, 12, 0.3, 0 })
	end)

	t.test("WatchLeftColumn hands over the column once it exists, or straight away", function()
		local UITheme, playerGui = theme({})
		local seen = {}
		UITheme.WatchLeftColumn(function(column)
			table.insert(seen, column)
		end)
		t.eq(#seen, 0, "no column yet")
		UITheme.LeftColumn(Instance.new("Frame"), 1)
		UITheme.LeftColumn(Instance.new("Frame"), 2)
		local column = playerGui:FindFirstChild("LeftColumn"):FindFirstChild("Column")
		t.eq(#seen, 1, "once, when it's made")
		t.ok(seen[1] == column)
		UITheme.WatchLeftColumn(function(c)
			table.insert(seen, c)
		end)
		t.eq(#seen, 2, "a late watcher gets it at once")
		t.ok(seen[2] == column)
	end)

	t.test("the theme's danger colour is #C0503A", function()
		local UITheme = theme({})
		local danger = UITheme.Colors.Danger
		t.eq(
			{ math.floor(danger.R * 255 + 0.5), math.floor(danger.G * 255 + 0.5), math.floor(danger.B * 255 + 0.5) },
			{ 192, 80, 58 }
		)
	end)

	t.test("a chat box that can't be read counts as 0 instead of erroring", function()
		local bar = { Enabled = true, AbsolutePosition = Vector2.new(8, 224), AbsoluteSize = Vector2.new(300, 36) }
		t.eq(columnAt({ ChatWindowConfiguration = unreadable(true) }), { 0, 12, 0.3, 0 })
		-- The other one still counts.
		t.eq(
			columnAt({ ChatWindowConfiguration = unreadable(true), ChatInputBarConfiguration = bar }),
			{ 0, 12, 0, 270 }
		)
	end)
end
