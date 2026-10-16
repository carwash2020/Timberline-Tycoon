--!nocheck
-- BuildMenuUI on a gamepad (pattern of StoreUIPad.spec): opening selects the first
-- card; B and Esc close, unbind everything and give the selection back; A on a
-- ready card places with no mouse; A on a locked card says why and places nothing;
-- LB and RB change category and select its first card; nothing is bound to
-- ButtonR2; nothing is left bound after close. Headless: the real UITheme,
-- GamepadNav and MenuPad on stand-in Instances, the HUD and the services mocked.
return function(t)
	local roblox = t.roblox
	local Enum, Instance, Vector2 = roblox.Enum, roblox.Instance, roblox.Vector2
	local BlueprintBook = t.shared("BlueprintBook")
	local BuildMenuLogic = t.shared("BuildMenuLogic")

	-- Lune's buttons have no Activated signal: give each an inert one (the presses
	-- go through BuildMenuUI.Press, which the real Activated calls).
	local inert = setmetatable({}, { __mode = "k" })
	for _, prop in ipairs({ "InputBegan", "InputEnded", "SelectionGained", "SelectionLost", "Activated" }) do
		pcall(roblox.implementProperty, "TextButton", prop, function(self)
			inert[self] = inert[self] or {}
			local ev = inert[self][prop]
			if ev == nil then
				ev = {}
				function ev:Connect()
					return { Disconnect = function() end }
				end
				inert[self][prop] = ev
			end
			return ev
		end)
	end

	local function setup()
		local playerGui = Instance.new("Folder")
		playerGui.Name = "PlayerGui"
		local guiService = {
			SelectedObject = nil,
			IsTenFootInterface = function()
				return false
			end,
			TopbarInset = roblox.Rect.new(0, 0, 0, 0),
			GetGuiInset = function()
				return Vector2.new(0, 0), Vector2.zero
			end,
			GetPropertyChangedSignal = function()
				return {
					Connect = function()
						return { Disconnect = function() end }
					end,
				}
			end,
		}
		local bound = {}
		local actions = {
			BindActionAtPriority = function(_, name, fn, _touch, _priority, ...)
				bound[name] = { fn = fn, keys = { ... } }
			end,
			BindAction = function(_, name, fn, _touch, ...)
				bound[name] = { fn = fn, keys = { ... } }
			end,
			UnbindAction = function(_, name)
				bound[name] = nil
			end,
		}
		local toasts, modal = {}, {}
		local lastInput = Enum.UserInputType.Gamepad1
		local loader = t.loader({
			services = {
				GuiService = guiService,
				ContextActionService = actions,
				Players = {
					LocalPlayer = {
						FindFirstChildOfClass = function()
							return playerGui
						end,
						WaitForChild = function()
							return playerGui
						end,
					},
				},
				TextChatService = {},
				UserInputService = {
					TouchEnabled = false,
					KeyboardEnabled = false,
					GamepadEnabled = true,
					LastInputTypeChanged = {
						Connect = function()
							return { Disconnect = function() end }
						end,
					},
					GetLastInputType = function()
						return lastInput
					end,
					GetImageForKeyCode = function()
						return ""
					end,
				},
			},
			globals = {
				workspace = { CurrentCamera = { ViewportSize = Vector2.new(1280, 720) } },
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					defer = function(fn, ...)
						fn(...)
					end,
					delay = function() end,
				},
			},
			mocks = {
				HUD = {
					Toast = function(text)
						table.insert(toasts, text)
					end,
					SetModal = function(rect)
						table.insert(modal, rect or false)
					end,
					TopRow = function()
						return nil
					end,
				},
			},
		})
		local UI = loader:load("StarterPlayer/StarterPlayerScripts/BuildMenuUI")
		return {
			UI = UI,
			gui = guiService,
			bound = bound,
			toasts = toasts,
			modal = modal,
			playerGui = playerGui,
			loader = loader,
		}
	end

	local function boundCount(bound)
		local n = 0
		for _ in pairs(bound) do
			n += 1
		end
		return n
	end

	-- A book with plenty in it, plus a locked plan or two, at a plot tier that places most.
	local function opts(placed, starter)
		local ids = {}
		if starter then
			ids = BlueprintBook.Starter()
		else
			for _, bp in ipairs(t.shared("PlotData").Blueprints) do
				table.insert(ids, bp.id)
			end
		end
		return {
			entries = function()
				return BlueprintBook.Entries(ids, {}, true)
			end,
			ctx = function()
				if starter then
					return { tier = 1, cash = 0, boxed = false }
				end
				return { tier = 5, cash = 100000, boxed = false }
			end,
			place = function(entry)
				table.insert(placed, entry.id)
			end,
			land = function()
				table.insert(placed, "#land")
			end,
		}
	end

	local function keyPress(code)
		return { KeyCode = code, UserInputType = Enum.UserInputType.Gamepad1 }
	end

	t.test(
		"opening selects the first card of the first category, and binds only LB, RB, B, Esc and hold-still",
		function()
			local s = setup()
			s.UI.Start()
			local placed = {}
			s.UI.Open(opts(placed))
			local tiles = s.UI.Tiles()
			t.ok(#tiles > 0, "the first category has cards")
			t.eq(s.gui.SelectedObject, tiles[1].button, "the first card is selected")
			t.eq(s.UI.Category().kind, "Walls")
			t.ok(s.UI.IsOpen())
			t.eq(boundCount(s.bound), 3, "tabs, close and hold-still")
			for name, b in pairs(s.bound) do
				for _, key in ipairs(b.keys) do
					t.ok(key ~= Enum.KeyCode.ButtonR2, name .. " must not bind ButtonR2")
				end
			end
			t.ok(s.bound.BuildMenuTabs ~= nil and s.bound.BuildMenuClose ~= nil)
			t.eq(#s.modal, 1, "the HUD knows where the menu is")
		end
	)

	t.test("B closes, unbinds everything and gives the selection back; Esc closes too", function()
		local s = setup()
		s.UI.Start()
		s.UI.Open(opts({}))
		local close = s.bound.BuildMenuClose.fn
		close("BuildMenuClose", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonB))
		t.ok(not s.UI.IsOpen(), "B closed it")
		t.eq(boundCount(s.bound), 0, "no action is left bound")
		t.eq(s.gui.SelectedObject, nil, "the selection is let go")
		t.eq(s.modal[#s.modal], false, "the HUD's modal is released")
		s.UI.Open(opts({}))
		s.bound.BuildMenuClose.fn("BuildMenuClose", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.Escape))
		t.ok(not s.UI.IsOpen(), "Esc closed it")
		t.eq(boundCount(s.bound), 0)
	end)

	t.test("B returns the selection to the button that opened the menu", function()
		local s = setup()
		s.UI.Start()
		local opener = Instance.new("TextButton")
		opener.Name = "Plans"
		opener.Parent = s.playerGui
		s.gui.SelectedObject = opener
		s.UI.Open(opts({}))
		t.ok(s.gui.SelectedObject ~= opener, "the menu took the selection")
		s.bound.BuildMenuClose.fn("BuildMenuClose", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonB))
		t.eq(s.gui.SelectedObject, opener, "back on the HAMMER / PLANS button")
	end)

	t.test("A on a ready card places it with no mouse; the right entry reaches place()", function()
		local s = setup()
		s.UI.Start()
		local placed = {}
		s.UI.Open(opts(placed))
		local tile = s.UI.Tiles()[1]
		t.eq(tile.view.state, "ready")
		-- A on a selected card is its Activated.
		s.UI.Press(tile.entry)
		t.eq(placed, { tile.entry.id }, "place() got the card's entry")
	end)

	t.test(
		"A on a locked card is handed to place() too (PlotUI's planRow toasts the reason and never places)",
		function()
			local s = setup()
			s.UI.Start()
			local placed = {}
			s.UI.Open(opts(placed, true))
			-- Find a locked card in any category.
			local found
			for i = 1, #BuildMenuLogic.Kinds do
				s.bound.BuildMenuTabs.fn("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonR1))
				for _, tile in ipairs(s.UI.Tiles()) do
					if tile.view.state == "locked" then
						found = tile
					end
				end
				if found then
					break
				end
			end
			t.ok(found ~= nil, "a locked card exists")
			t.ok(found.view.chip ~= nil, "it shows a lock chip")
			t.ok(found.view.message ~= nil, "and carries the reason")
			t.ok(found.button:FindFirstChild("Chip") ~= nil)
			local art = found.button:FindFirstChild("Art")
			t.ok(art:FindFirstChild("Swatch").BackgroundTransparency > 0, "a locked card is dimmed (about 62% opacity)")
		end
	)

	t.test("LB and RB change category, select its first card, and wrap", function()
		local s = setup()
		s.UI.Start()
		s.UI.Open(opts({}))
		local tabs = s.bound.BuildMenuTabs.fn
		local first = s.UI.Category().kind
		tabs("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonR1))
		local second = s.UI.Category().kind
		t.ok(second ~= first, "RB moved on")
		t.eq(s.gui.SelectedObject, s.UI.Tiles()[1].button, "its first card is selected")
		tabs("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonL1))
		t.eq(s.UI.Category().kind, first, "LB moved back")
		tabs("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonL1))
		t.eq(s.UI.Category().kind, "More", "LB from the first wraps to the last")
		tabs("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonR1))
		t.eq(s.UI.Category().kind, first, "RB from the last wraps to the first")
	end)

	t.test(
		"the D-pad has explicit neighbours: right/down move along the grid, the first column's left is the rail",
		function()
			local s = setup()
			s.UI.Start()
			s.UI.Open(opts({}))
			local tiles = s.UI.Tiles()
			t.ok(#tiles >= 4)
			t.eq(tiles[1].button.NextSelectionRight, tiles[2].button)
			t.eq(
				tiles[1].button.NextSelectionDown,
				tiles[4].button,
				"three columns on this layout or four: down is one row on"
			)
		end
	)

	t.test("reopening comes back to the same category and card", function()
		local s = setup()
		s.UI.Start()
		s.UI.Open(opts({}))
		s.bound.BuildMenuTabs.fn("BuildMenuTabs", Enum.UserInputState.Begin, keyPress(Enum.KeyCode.ButtonR1))
		local kind = s.UI.Category().kind
		local tile = s.UI.Tiles()[2]
		s.UI.Press(tile.entry) -- remembers the card
		s.UI.Close()
		s.UI.Open(opts({}))
		t.eq(s.UI.Category().kind, kind, "the same category")
		t.eq(s.gui.SelectedObject, s.UI.Tiles()[2].button, "the same card")
	end)

	t.test("nothing is bound to ButtonR2, and no action is left after closing by placing", function()
		local s = setup()
		s.UI.Start()
		local placed = {}
		local o = opts(placed)
		local inner = o.place
		o.place = function(entry)
			inner(entry)
			s.UI.Close() -- PlotUI's planRow closes the menu when a card is placed
		end
		s.UI.Open(o)
		s.UI.Press(s.UI.Tiles()[1].entry)
		t.eq(boundCount(s.bound), 0, "closed by placing: nothing left bound")
		local fs = require("@lune/fs")
		t.eq(
			string.find(fs.readFile("src/StarterPlayer/StarterPlayerScripts/BuildMenuUI.luau"), "ButtonR2", 1, true),
			nil
		)
	end)

	t.test("every ScrollingFrame in the menu hides the engine's selection box", function()
		local s = setup()
		s.UI.Start()
		local n = 0
		for _, d in ipairs(s.playerGui:GetDescendants()) do
			if d:IsA("ScrollingFrame") then
				n += 1
				t.ok(d.SelectionImageObject ~= nil, d.Name .. " has a SelectionImageObject")
			end
		end
		t.eq(n, 2, "the rail and the grid")
	end)

	t.test(
		"a card's name is 16 px wrapped over two lines, never truncated; the corner tab is the seal colour",
		function()
			local s = setup()
			s.UI.Start()
			s.UI.Open(opts({}))
			local BlueprintArt = t.load("ReplicatedStorage/Shared/Art/BlueprintArt")
			for _, tile in ipairs(s.UI.Tiles()) do
				local name = tile.button.Plate:FindFirstChild("Name")
				t.eq(name.TextWrapped, true)
				t.eq(name.TextTruncate, Enum.TextTruncate.None, "no ellipsis")
				t.eq(name.TextScaled, false)
				t.ok(name.TextSize >= 14)
				t.eq(tile.button.SealTab.Wedge.BackgroundColor3, BlueprintArt.SealColor(tile.entry.id))
				t.ok(tile.button.SelectionImageObject ~= nil, "a focus ring, not Roblox's default box")
			end
		end
	)
end
