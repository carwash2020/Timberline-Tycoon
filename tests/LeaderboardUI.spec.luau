--!nocheck
-- The Leaderboard tab: every button and row is selectable and linked for the
-- D-pad, TV text is 18 px, the three states read right, the client asks at
-- most once per ten seconds, and B backs out of the tab like Visitors.
return function(t)
	local UDim2 = t.roblox.UDim2

	-- Lune's Instances have no GUI events and take no Instance in a
	-- NextSelection property, so the tab runs on plain tables here: they
	-- keep the properties it sets, and a Parent adds the child.
	local Instance = {}
	function Instance.new(className)
		local object = { ClassName = className, Name = className, Selectable = true, _children = {} }
		function object:FindFirstChild(name)
			for _, child in ipairs(self._children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		return setmetatable(object, {
			__newindex = function(self, key, value)
				rawset(self, key, value)
				if key == "Parent" and type(value) == "table" and value._children then
					table.insert(value._children, self)
				end
			end,
		})
	end

	-- Lune's Instances have no GUI events, so the buttons UITheme builds are
	-- faked here: a face with the properties the tab sets and a signal.
	local function fakeTheme()
		local C = setmetatable({}, {
			__index = function()
				return t.roblox.Color3.new(1, 1, 1)
			end,
		})
		local theme = { Colors = C, Fonts = { Black = t.roblox.Enum.Font.Arial, Bold = t.roblox.Enum.Font.Arial } }
		function theme.list()
			return Instance.new("UIListLayout")
		end
		function theme.corner() end
		function theme.label(parent, text, _font, size)
			local l = Instance.new("TextLabel")
			l.Text = text
			l.TextSize = size
			l.Parent = parent
			return l
		end
		function theme.Button(opts)
			local signal = { handlers = {} }
			function signal:Connect(fn)
				table.insert(self.handlers, fn)
			end
			function signal:Fire()
				for _, fn in ipairs(self.handlers) do
					fn()
				end
			end
			local face = {
				Name = "Face",
				Text = opts.text,
				TextSize = opts.textSize,
				Selectable = true,
				Activated = signal,
			}
			local root = Instance.new("Frame")
			root.Size = UDim2.fromOffset(opts.size.X, opts.size.Y + 3)
			local button = { root = root, face = face, style = opts.style }
			function button.SetStyle(self, style)
				self.style = style
			end
			function button.SetText(_self, text)
				face.Text = text
			end
			return button
		end
		return theme
	end

	local function boot(tenFoot)
		local clock = 100
		local loader = t.loader({
			services = {
				GuiService = {
					SelectedObject = nil,
					IsTenFootInterface = function()
						return tenFoot == true
					end,
					TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
					GetGuiInset = function()
						return t.roblox.Vector2.new(0, 58), t.roblox.Vector2.zero
					end,
				},
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			},
			globals = {
				os = setmetatable({
					clock = function()
						return clock
					end,
				}, { __index = os }),
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
				},
				workspace = {},
				Instance = Instance,
			},
			mocks = {
				Net = {
					Remote = function()
						return {}
					end,
				},
				UITheme = fakeTheme(),
			},
		})
		local UI = loader:load("StarterPlayer/StarterPlayerScripts/LeaderboardUI")
		local Logic = loader:shared("LeaderboardLogic")
		local on = false
		local asks, saved = 0, {}
		local parent = Instance.new("Frame")
		local panel = UI.Build(parent, 60, function()
			return on
		end, function(value)
			on = value
			table.insert(saved, value)
		end, function()
			asks += 1
		end)
		return {
			UI = UI,
			Logic = Logic,
			panel = panel,
			parent = parent,
			asks = function()
				return asks
			end,
			saved = saved,
			setOn = function(value)
				on = value
			end,
			advance = function(seconds)
				clock += seconds
			end,
		}
	end

	local function rows(n)
		local out = {}
		for i = 1, n do
			table.insert(out, { rank = i, name = "Player" .. i, score = 1000000 - i })
		end
		return out
	end

	local function textOf(row, child)
		return row:FindFirstChild(child).Text
	end

	t.test("it starts on the loading line, hidden, with nothing to select but the toggle and Refresh", function()
		local env = boot(false)
		t.eq(env.panel.root.Visible, false)
		t.eq(env.panel.status.Text, "Loading the board...")
		t.eq(#env.panel:Chain(), 2)
		t.ok(env.panel:First() == env.panel.toggle.face)
	end)

	t.test("the toggle is off by default, says so, and saves through the setting callback", function()
		local env = boot(false)
		env.panel.root.Visible = true
		env.panel:Show()
		t.ok(string.find(env.panel.toggle.face.Text, "Show me on the leaderboard", 1, true) ~= nil)
		t.ok(string.find(env.panel.toggle.face.Text, "OFF", 1, true) ~= nil)
		env.panel.toggle.face.Activated:Fire()
		t.eq(env.saved, { true })
		env.panel:SetOptIn(true)
		t.ok(string.find(env.panel.toggle.face.Text, "ON", 1, true) ~= nil)
	end)

	t.test("rows show rank, name and cash; your own row follows when you are opted in", function()
		local env = boot(false)
		env.panel.root.Visible = true
		env.setOn(true)
		env.panel:Receive({ ok = true, rows = rows(10), me = { score = 4321, rank = nil } })
		local visible = 0
		for _, row in ipairs(env.panel.rows) do
			if row.Visible then
				visible += 1
			end
		end
		t.eq(visible, 10)
		t.eq(textOf(env.panel.rows[1], "Rank"), "1")
		t.eq(textOf(env.panel.rows[1], "Name"), "Player1")
		t.eq(textOf(env.panel.rows[1], "Cash"), "$999,999")
		t.eq(env.panel.status.Visible, false)
		t.eq(env.panel.meRow.Visible, true)
		t.eq(textOf(env.panel.meRow, "Rank"), "-")
		t.eq(textOf(env.panel.meRow, "Cash"), "$4,321")
		env.setOn(false)
		env.panel:SetOptIn(false)
		t.eq(env.panel.meRow.Visible, false, "opted out: no own row")
	end)

	t.test("empty, failed and loading states", function()
		local env = boot(false)
		env.panel.root.Visible = true
		env.panel:Receive({ ok = true, rows = {} })
		t.eq(env.panel.status.Visible, true)
		t.eq(env.panel.status.Text, "No one is on the board yet")
		env.panel:Receive({ ok = false, rows = {} })
		t.eq(env.panel.status.Text, "Couldn't load the board. Try again soon.")
		env.panel:Receive("garbage")
		t.eq(env.panel.status.Text, "Couldn't load the board. Try again soon.", "junk from the server changes nothing")
		env.panel:Receive({ ok = true, rows = rows(3) })
		t.eq(env.panel.status.Visible, false)
		t.eq(env.panel.rows[4].Visible, false)
	end)

	t.test("everything pressable or walkable is selectable and linked top to bottom for the D-pad", function()
		local env = boot(false)
		env.panel.root.Visible = true
		local tab = Instance.new("TextButton")
		env.panel:Receive({ ok = true, rows = rows(10), me = { score = 5, rank = nil } })
		env.setOn(true)
		env.panel:Render({ ok = true, rows = rows(10), me = { score = 5, rank = nil } })
		env.panel:Link(tab)
		local chain = env.panel:Chain()
		t.eq(#chain, 2 + 10 + 1)
		t.ok(tab.NextSelectionDown == env.panel.toggle.face)
		t.ok(chain[1].NextSelectionUp == tab)
		t.ok(chain[1].NextSelectionDown == chain[2])
		t.ok(chain[2] == env.panel.refresh.face)
		for i, object in ipairs(chain) do
			t.ok(object.Selectable ~= false, object.Name .. " is selectable")
			t.ok(object.NextSelectionDown == chain[i + 1])
			if i > 1 then
				t.ok(object.NextSelectionUp == chain[i - 1])
			end
		end
		t.eq(chain[#chain].NextSelectionDown, nil, "the pad stops at the last row")
		t.ok(chain[#chain] == env.panel.meRow)
	end)

	t.test("while the tab is hidden the tab button does not point at it", function()
		local env = boot(false)
		local tab = Instance.new("TextButton")
		env.panel.root.Visible = true
		env.panel:Link(tab)
		t.ok(tab.NextSelectionDown == env.panel.toggle.face)
		env.panel.root.Visible = false
		env.panel:Link(tab)
		t.ok(tab.NextSelectionDown == nil)
	end)

	t.test("touch targets: the toggle and Refresh are at least 44 px tall", function()
		local env = boot(false)
		local InputKit = env.UI and t.shared("InputKit")
		t.ok(env.panel.toggle.root.Size.Y.Offset - 3 >= InputKit.MinTouchPx)
		t.ok(env.panel.refresh.root.Size.Y.Offset - 3 >= InputKit.MinTouchPx)
		t.eq(env.panel.toggle.root.Size.X.Scale, 1, "full width: nothing spills out of a 375 wide card")
	end)

	t.test("text is 14 px in hand and 18 px on a TV", function()
		local hand = boot(false)
		local tv = boot(true)
		t.eq(hand.panel.rows[1]:FindFirstChild("Name").TextSize, 14)
		t.eq(tv.panel.rows[1]:FindFirstChild("Name").TextSize, 18)
		t.eq(tv.panel.rows[1]:FindFirstChild("Cash").TextSize, 18)
		t.eq(tv.panel.status.TextSize, 18)
		t.eq(tv.panel.toggle.face.TextSize, 18)
		t.ok(tv.panel.rows[1].Size.Y.Offset >= tv.panel.rows[1]:FindFirstChild("Name").TextSize)
	end)

	t.test("the client asks the server at most once per ten seconds", function()
		local env = boot(false)
		env.panel.root.Visible = true
		env.panel:Show()
		t.eq(env.asks(), 1)
		env.advance(3)
		env.panel.refresh.face.Activated:Fire()
		t.eq(env.asks(), 1, "too soon: redraws, no request")
		env.advance(7)
		env.panel.refresh.face.Activated:Fire()
		t.eq(env.asks(), 1, "10 s since the ask, but the margin keeps it clear of the server's edge")
		env.advance(2)
		env.panel.refresh.face.Activated:Fire()
		t.eq(env.asks(), 2)
	end)

	t.test("B and Esc leave the Leaderboard tab for the game list", function()
		local gui = { SelectedObject = nil }
		local loader = t.loader({
			services = {
				ContextActionService = {},
				GuiService = gui,
				Players = { LocalPlayer = {} },
				TextChatService = {},
				UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			},
			mocks = {
				HUD = {},
				BlueprintPlacer = {},
				CameraShake = {},
				Quality = {},
				SoundData = {},
				LeaderboardUI = {},
				UITheme = fakeTheme(),
			},
		})
		local SettingsUI = loader:load("StarterPlayer/StarterPlayerScripts/SettingsUI")
		t.eq(SettingsUI.BackTarget("board"), "game")
		t.eq(SettingsUI.BackTarget("visitors"), "game")
		t.eq(SettingsUI.BackTarget("game"), nil, "from the game list B closes the card")
		t.eq(SettingsUI.BackTarget("nope"), nil)
		local Logic = loader:shared("SettingsLogic")
		t.eq(Logic.Tabs, { "game", "visitors", "board" })
	end)
end
