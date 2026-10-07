--!nocheck
-- The join screen: "Lower quality (best for phones)" or "Higher quality (Xbox,
-- PC, tablets)". It appears once the save has loaded and nothing has been chosen,
-- pre-selects what the device recommends, can be used with a gamepad, a tap or a
-- click, and sends the choice to the server (SetQuality) and to Quality.
return function(t)
	local roblox = t.roblox
	local Instance, Enum = roblox.Instance, roblox.Enum
	local QualityProfile = t.shared("QualityProfile")

	-- Lune's buttons have no input signals: give each button its own, so the spec can press one.
	local signals = _G.__qualitySignals or setmetatable({}, { __mode = "k" })
	_G.__qualitySignals = signals
	local function signalFor(self, prop)
		signals[self] = signals[self] or {}
		local ev = signals[self][prop]
		if ev == nil then
			local fns = {}
			ev = {}
			function ev:Connect(fn)
				table.insert(fns, fn)
				return { Disconnect = function() end }
			end
			function ev:Fire(...)
				for _, fn in ipairs(table.clone(fns)) do
					fn(...)
				end
			end
			signals[self][prop] = ev
		end
		return ev
	end
	for _, prop in ipairs({ "InputBegan", "InputEnded", "SelectionGained", "SelectionLost", "Activated" }) do
		pcall(roblox.implementProperty, "TextButton", prop, function(self)
			return signalFor(self, prop)
		end)
	end

	-- A client: `touchOnly` is a phone, `console` a gamepad on a TV.
	local function client(opts)
		opts = opts or {}
		local c = { fired = {}, refreshed = 0, attributes = {}, listeners = {}, controls = {} }
		c.attributes.ProfileLoaded = opts.loaded
		c.attributes.SettingQuality = opts.saved
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local controls = {
			Enable = function()
				table.insert(c.controls, "on")
			end,
			Disable = function()
				table.insert(c.controls, "off")
			end,
		}
		local player = {
			GetAttribute = function(_, name)
				return c.attributes[name]
			end,
			SetAttribute = function(_, name, value)
				c.attributes[name] = value
				for _, fn in ipairs(c.listeners[name] or {}) do
					fn()
				end
			end,
			GetAttributeChangedSignal = function(_, name)
				return {
					Connect = function(_, fn)
						c.listeners[name] = c.listeners[name] or {}
						table.insert(c.listeners[name], fn)
					end,
				}
			end,
			WaitForChild = function(_, name)
				return if name == "PlayerGui" then playerGui else nil
			end,
			FindFirstChild = function()
				return nil
			end,
		}
		c.gui = { SelectedObject = nil }
		function c.gui.IsTenFootInterface()
			return opts.console == true
		end
		c.playerGui = playerGui
		local remote = {
			FireServer = function(_, value)
				table.insert(c.fired, value)
			end,
		}
		local loader = t.loader({
			globals = {
				workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(opts.touch and 800 or 1280, 720) } },
				task = {
					defer = function() end, -- (the click sound)
				},
			},
			services = {
				GuiService = c.gui,
				Players = { LocalPlayer = player },
				UserInputService = {
					TouchEnabled = opts.touch == true,
					KeyboardEnabled = opts.touch ~= true and opts.console ~= true,
					GetLastInputType = function()
						return if opts.touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseMovement
					end,
					InputBegan = { Connect = function() end },
				},
				TextChatService = {},
			},
			mocks = {
				Net = {
					Remote = function(name)
						assert(name == "SetQuality", name)
						return remote
					end,
				},
				Quality = {
					TouchOnly = function()
						return opts.touch == true
					end,
					Refresh = function()
						c.refreshed += 1
					end,
				},
			},
		})
		c.UI = loader:load("StarterPlayer/StarterPlayerScripts/QualityPickerUI")
		c.UI._controls = function()
			return controls
		end
		c.player = player
		function c.screen()
			return c.playerGui:FindFirstChild("QualityPicker")
		end
		return c
	end

	local function find(inst, name)
		return inst:FindFirstChild(name, true)
	end

	t.test("it stays hidden until the save has loaded, and shows only while nothing is chosen", function()
		local c = client({ loaded = false, saved = "unset" })
		c.UI.Start()
		t.eq(c.screen().Enabled, false, "the save has not loaded")
		c.player:SetAttribute("ProfileLoaded", true)
		t.eq(c.screen().Enabled, true, "it appears once the save loads")
		-- A save that already chose (an old one on another device) never sees it.
		for _, saved in ipairs({ "low", "high" }) do
			local done = client({ loaded = true, saved = saved })
			done.UI.Start()
			t.eq(done.screen().Enabled, false, "chosen: " .. saved)
		end
		-- A new save and an old one both start "unset" and see it once.
		local old = client({ loaded = true, saved = nil })
		old.UI.Start()
		t.eq(old.screen().Enabled, true)
	end)

	t.test("two big buttons say Lower (best for phones) and Higher (Xbox, PC, tablets) with a line each", function()
		local c = client({ loaded = true, saved = "unset" })
		c.UI.Start()
		local screen = c.screen()
		local low, high = find(screen, "ChooseLower"), find(screen, "ChooseHigher")
		t.ok(low and low:IsA("TextButton"), "a button for Lower")
		t.ok(high and high:IsA("TextButton"))
		local function texts(button)
			local out = {}
			for _, d in ipairs(button:GetDescendants()) do
				if d:IsA("TextLabel") then
					out[d.Name] = d.Text
				end
			end
			return out
		end
		local l, h = texts(low), texts(high)
		t.eq(l.Title, "Lower quality")
		t.ok(string.find(l.Device, "best for phones", 1, true))
		t.eq(l.Blurb, QualityProfile.Options.low.blurb)
		t.eq(h.Title, "Higher quality")
		t.ok(string.find(h.Device, "Xbox, PC, tablets", 1, true))
		t.eq(h.Blurb, QualityProfile.Options.high.blurb)
		t.eq(find(screen, "Title").Text, QualityProfile.PickerTitle)
		t.ok(string.find(find(screen, "Hint").Text, "Settings", 1, true), "it says it can be changed later")
		-- A fingertip on a phone, and readable text, and selectable for a gamepad.
		for _, button in ipairs({ low, high }) do
			t.ok(button.Selectable)
			t.eq(button.Size.Y, roblox.UDim.new(1, 0), "as tall as the row, which is at least 170 studs")
			for _, d in ipairs(button:GetDescendants()) do
				if d:IsA("TextLabel") then
					t.ok(d.TextSize >= 14 or d.Text == " ", d.Name .. " is 14 px or more")
				end
			end
		end
		local limit = find(screen, "Panel"):FindFirstChildOfClass("UISizeConstraint")
		t.ok(
			limit.MinSize.Y - 28 - 62 >= 44 * 3,
			"the cards are far taller than a fingertip even in the smallest panel"
		)
		t.eq(low.NextSelectionRight, high, "the stick moves between them")
		t.eq(high.NextSelectionLeft, low)
	end)

	t.test(
		"the recommendation is marked and, on a gamepad, pre-selected: a phone gets Lower, a console or PC Higher",
		function()
			local phone = client({ loaded = true, saved = "unset", touch = true })
			phone.UI.Start()
			t.eq(find(phone.screen(), "ChooseLower"):FindFirstChild("Tag").Text, QualityProfile.RecommendedTag)
			t.eq(
				string.match(find(phone.screen(), "ChooseHigher"):FindFirstChild("Tag").Text, "%S") == nil,
				true,
				"only one is marked"
			)
			t.eq(phone.gui.SelectedObject, nil, "a touch screen gets no selection ring")
			local pad = client({ loaded = true, saved = "unset", console = true })
			pad.UI.Start()
			t.eq(find(pad.screen(), "ChooseHigher"):FindFirstChild("Tag").Text, QualityProfile.RecommendedTag)
			t.eq(
				pad.gui.SelectedObject,
				find(pad.screen(), "ChooseHigher"),
				"A is enough on an Xbox: Higher is selected"
			)
			local pc = client({ loaded = true, saved = "unset" })
			pc.UI.Start()
			t.eq(find(pc.screen(), "ChooseHigher"):FindFirstChild("Tag").Text, QualityProfile.RecommendedTag)
			t.eq(pc.gui.SelectedObject, nil, "a mouse gets no ring")
		end
	)

	t.test("choosing sends SetQuality, tells Quality, closes the screen, and never shows again", function()
		for _, case in ipairs({ { "ChooseLower", "low" }, { "ChooseHigher", "high" } }) do
			local c = client({ loaded = true, saved = "unset", console = true })
			c.UI.Start()
			t.eq(c.controls, { "off" }, "the character does not walk while it is up")
			t.ok(find(c.screen(), case[1]), case[1] .. " is on the screen")
			c.UI.Choose(case[2]) -- (what the card's Activated runs, after the click sound)
			t.eq(c.fired, { case[2] }, "one choice sent")
			t.eq(c.player:GetAttribute("SettingQuality"), case[2], "mirrored at once")
			t.eq(c.refreshed >= 1, true, "Quality re-reads")
			t.eq(c.screen().Enabled, false)
			t.eq(c.controls, { "off", "on" }, "walking again")
			t.eq(c.gui.SelectedObject, nil, "the pad is let go")
			-- Not twice.
			c.UI.Choose("low")
			t.eq(#c.fired, 1)
			c.player:SetAttribute("SettingQuality", "unset") -- (a slot swap re-mirrored an unchosen save: still not again this session)
			t.eq(c.screen().Enabled, false)
		end
	end)

	t.test("it only takes a real choice", function()
		local c = client({ loaded = true, saved = "unset" })
		c.UI.Start()
		for _, bad in ipairs({ "unset", "medium", "", 1 }) do
			c.UI.Choose(bad)
			t.eq(#c.fired, 0)
			t.eq(c.screen().Enabled, true)
		end
	end)

	t.test("it sits over every other screen, and is wired into the client", function()
		local fs = require("@lune/fs")
		local L = client({ loaded = true, saved = "low" }).UI.Layers
		L = L
			or t.loader({
				globals = { workspace = { CurrentCamera = { ViewportSize = roblox.Vector2.new(1280, 720) } } },
				services = {
					GuiService = {
						IsTenFootInterface = function()
							return false
						end,
					},
					Players = { LocalPlayer = {} },
					UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
					TextChatService = {},
				},
			})
				:load("StarterPlayer/StarterPlayerScripts/UITheme").Layers
		for name, order in pairs(L) do
			if name ~= "QualityPicker" then
				t.ok(L.QualityPicker > order, "over " .. name)
			end
		end
		local client = fs.readFile("src/StarterPlayer/StarterPlayerScripts/Client.client.luau")
		t.ok(string.find(client, "require(script.Parent.QualityPickerUI)", 1, true))
		t.ok(string.find(client, "require(script.Parent.QualityDressing)", 1, true))
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/QualityPickerUI.luau")
		t.ok(string.find(source, "GamepadNav.Focus(", 1, true), "the gamepad selection is GamepadNav's")
		t.ok(string.find(source, "GamepadNav.Restore(", 1, true))
		t.ok(string.find(source, "QualityPickerUI.Choose(choice)", 1, true), "a card's press chooses its own option")
		t.eq(string.find(source, "DisplayOrder", 1, true), nil, "UITheme.Layers decides")
	end)

	t.test("Settings has a Graphics: Lower / Higher row that sends the other choice", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SettingsUI.luau")
		t.ok(string.find(source, 'graphicsFace = row("graphics", "Graphics: Higher", function()', 1, true))
		t.ok(string.find(source, "QualityProfile.RowText(", 1, true))
		t.ok(string.find(source, "QualityProfile.Other(current)", 1, true))
		t.ok(string.find(source, 'Net.Remote("SetQuality"):FireServer(nextChoice)', 1, true))
		t.eq(string.find(source, "SetOverride", 1, true), nil, "the old four-way override is gone from the menu")
	end)
end
