--!nocheck
-- The mill's cut panel: a prompt opens it, the buttons clear a phone,
-- and the D-pad (plus arrows) changes X and Y without taking the HUD's keys.
return function(t)
	local Enum = t.roblox.Enum
	local Vector2 = t.roblox.Vector2
	local modalLog = {}
	-- GetGuiInset's top left. It has no notch. ScreenGui.AbsolutePosition is neither.
	local guiInset = Vector2.zero
	local leftSafe = 0
	local loader = t.loader({
		services = {
			GuiService = {
				IsTenFootInterface = function()
					return false
				end,
				GetGuiInset = function()
					return guiInset
				end,
			},
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
		},
		mocks = {
			HUD = {
				SetModal = function(rect)
					table.insert(modalLog, { rect = rect })
				end,
				LeftSafe = function()
					return leftSafe
				end,
			},
		},
	})
	local Logic = loader:shared("SawmillLogic")
	local Input = loader:shared("InputKit")
	local MachineArt = loader:load("ReplicatedStorage/Shared/Art/MachineArt")
	local Controller = loader:load("StarterPlayer/StarterPlayerScripts/SawmillController")

	local function find(model, name, class)
		for _, d in ipairs(model:GetDescendants()) do
			if d.Name == name and (not class or d:IsA(class)) then
				return d
			end
		end
		return nil
	end

	t.test("the prompt opens the cut, and the board buttons are fingertip sized", function()
		local mill = MachineArt.Build("SawmillRickety", false)
		local prompt = find(mill, "CutPrompt", "ProximityPrompt")
		t.eq(prompt.ActionText, "Set the cut")
		t.eq(prompt.KeyboardKeyCode, Enum.KeyCode.E)
		t.eq(prompt.GamepadKeyCode, Enum.KeyCode.ButtonX)
		t.eq(prompt.RequiresLineOfSight, false)
		t.eq(prompt.ClickablePrompt, true)
		t.eq(prompt.MaxActivationDistance, Logic.PromptRange)
		for _, d in ipairs(mill:GetDescendants()) do
			if d:IsA("TextButton") then
				t.ok(d.Size.X.Offset >= Input.MinTouchPx and d.Size.Y.Offset >= Input.MinTouchPx, d.Name)
				t.eq(d.Active, true)
			end
		end
		local sign = find(mill, "Blockage", "BasePart")
		t.eq(sign.Transparency, 1)
		t.eq(find(sign, "TextLabel").Text, Logic.BlockageLabel)
		MachineArt.SetBlockage(mill, true)
		t.eq(sign.Transparency, 0)
		t.eq(sign:FindFirstChildWhichIsA("SurfaceGui").Enabled, true)
		MachineArt.SetBlockage(mill, false)
		t.eq(sign.Transparency, 1)
	end)

	t.test("the screen panel is 44 px on a phone and on a TV, and B closes it", function()
		for _, tenFoot in ipairs({ false, true }) do
			local panel = Controller.BuildPanel(tenFoot)
			local face = Logic.PanelFace(tenFoot)
			t.eq(panel.gui.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets)
			t.eq(#panel.buttons, 4)
			local names = {}
			for _, b in ipairs(panel.buttons) do
				names[b.Name] = { b:GetAttribute("Axis"), b:GetAttribute("Dir"), b.Size.X.Offset, b.Size.Y.Offset }
				t.ok(b.TextSize >= Input.MinTagPx, b.Name)
				t.eq(b.Selectable, true)
				t.eq(b.NextSelectionLeft, b, "the D-pad steps the cut instead of moving focus")
			end
			t.eq(names.XMinus, { "x", -1, face, face })
			t.eq(names.XPlus, { "x", 1, face, face })
			t.eq(names.YMinus, { "y", -1, face, face })
			t.eq(names.YPlus, { "y", 1, face, face })
			t.ok(panel.close.Size.Y.Offset >= Input.MinTouchPx, "close")
			t.ok(panel.readout.TextSize >= Input.MinTagPx, "the readout")
			t.eq(Input.TouchOk(face), true)
		end
		-- 667×375 scales by 375/480, clamped, and 0.7 is the floor.
		t.ok(Logic.PanelFace(false) * (375 / 480) >= Input.MinTouchPx, "667×375")
		t.ok(Logic.PanelFace(false) * 0.7 >= Input.MinTouchPx, "the compact floor")
	end)

	t.test("the client doesn't bind the HUD's D-pad shortcuts", function()
		local fs = require("@lune/fs")
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SawmillController.luau")
		t.eq(string.find(source, "Enum.KeyCode.DPad", 1, true), nil)
		t.ok(string.find(source, "SawmillLogic.PadStep", 1, true), "the open panel asks the logic for the key")
		t.ok(string.find(source, "SelectedObject", 1, true), "opening the panel takes the pad")
		t.ok(string.find(source, "SawmillLogic.PanelCloses", 1, true), "B and Esc close it")
		t.ok(string.find(source, "HUD.SetModal", 1, true), "the open card is a modal")
	end)

	t.test("opening sets the modal from the card, and the card clears the column and the hotbar", function()
		local panel = Controller.BuildPanel(false)
		-- A decoy: the engine can report this as (0, 0), and either way it
		-- is not the inset. Y is GetGuiInset; X is the notch probe.
		guiInset = Vector2.zero
		leftSafe = 0
		panel.gui.AbsolutePosition = Vector2.new(400, 250)
		panel.root.AbsolutePosition = Vector2.new(300, 90)
		panel.root.AbsoluteSize = Vector2.new(240, 200)
		Controller._open(panel)
		t.eq(panel.gui.Enabled, true)
		local opened = modalLog[#modalLog].rect
		t.eq(opened.left, 300)
		t.eq(opened.top, 90)
		t.eq(opened.right, 540)
		t.eq(opened.bottom, 290)
		Controller._close()
		t.eq(modalLog[#modalLog].rect, nil)

		-- GetGuiInset is (0, 58): the top bar, not the notch. leftSafe is 44.
		-- The card's position is inside the safe screen, and the rect HUD
		-- gets is that box plus this origin on the full screen.
		local inset = 58
		local notch = 44
		guiInset = Vector2.new(0, inset)
		leftSafe = notch
		panel.gui.AbsolutePosition = Vector2.new(0, 0)
		panel.gui.AbsoluteSize = Vector2.new(667, 317)
		panel.root.AbsolutePosition = Vector2.new(120, 40)
		panel.root.AbsoluteSize = Vector2.new(200, 160)
		Controller._open(panel)
		local shifted = modalLog[#modalLog].rect
		t.eq(shifted.left, 120 + notch)
		t.eq(shifted.top, 40 + inset)
		t.eq(shifted.right, 120 + notch + 200)
		t.eq(shifted.bottom, 200 + inset)

		local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		-- Origin (44, 58). The column {12, 48, 292, 228} is screen space.
		-- The card is placed in the inset gui, so adding the origin back
		-- must still miss that column. Sitting further right than the
		-- unshifted beside-slot would mean the notch was not subtracted.
		local placedScale = UITheme.ScaleFor(panel.gui.AbsoluteSize, false, false)
		local placedW, placedH = Logic.CardSize(false)
		local screenBox = {
			left = panel.root.Position.X.Offset + notch,
			top = panel.root.Position.Y.Offset + inset,
			right = panel.root.Position.X.Offset + notch + placedW * placedScale,
			bottom = panel.root.Position.Y.Offset + inset + placedH * placedScale,
		}
		local realColumn = { left = 12, top = 48, right = 292, bottom = 228 }
		t.eq(Logic.Overlaps(screenBox, realColumn), false, "screen column")
		t.ok(screenBox.left <= realColumn.right + 8, "against the shifted column")

		local function column(margin)
			return { left = margin, top = 48, right = margin + 280, bottom = 48 + 180 }
		end
		local cases = {
			{ w = 667, h = 375, ten = false, phone = true },
			{ w = 375, h = 667, ten = false, phone = true },
			{ w = 1920, h = 1080, ten = true, phone = false },
		}
		for _, c in ipairs(cases) do
			local viewport = Vector2.new(c.w, c.h)
			local scale = UITheme.ScaleFor(viewport, c.phone, c.ten)
			local cardW, cardH = Logic.CardSize(c.ten)
			local margin = if c.ten then 64 else 12
			local hotbar = if c.ten then 36 + 70 elseif c.phone then 12 + 58 else 12 + 70
			local box = Logic.PlaceCard(c.w, c.h, cardW * scale, cardH * scale, column(margin), c.h - hotbar)
			local label = c.w .. "x" .. c.h
			t.eq(Logic.Overlaps(box, column(margin)), false, label .. " column")
			t.ok(box.bottom <= c.h - hotbar, label .. " hotbar")
			t.ok(box.top >= 0 and box.left >= 0 and box.right <= c.w, label .. " on screen")
		end
	end)

	t.test("a 58 px inset keeps the card's on-screen bottom at or above the hotbar on a 667x375 phone", function()
		local roblox = t.roblox
		local UDim2 = roblox.UDim2
		local signals = _G.__screenGuiSignals
		if not signals then
			signals = {}
			_G.__screenGuiSignals = signals
			pcall(roblox.implementMethod, "ScreenGui", "GetPropertyChangedSignal", function(self, prop)
				local listeners = {}
				local ev = {
					Connect = function(_, fn)
						table.insert(listeners, fn)
						return { Disconnect = function() end }
					end,
					Fire = function()
						for _, fn in ipairs(listeners) do
							fn()
						end
					end,
				}
				signals[self] = signals[self] or {}
				signals[self][prop] = ev
				return ev
			end)
		end
		pcall(roblox.implementProperty, "TextButton", "Activated", function()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end)
		local function signal()
			return {
				Connect = function()
					return { Disconnect = function() end }
				end,
			}
		end
		local inset = 58
		local viewportH = 375
		local camera = { ViewportSize = Vector2.new(667, viewportH) }
		local attributes = { CoreLoopActive = 2 }
		local phonePlayer = roblox.Instance.new("Folder")
		local pg = roblox.Instance.new("Folder")
		pg.Name = "PlayerGui"
		pg.Parent = phonePlayer
		local phoneInset = Vector2.new(0, inset)
		local phoneLoader = t.loader({
			services = {
				GuiService = {
					IsTenFootInterface = function()
						return false
					end,
					GetGuiInset = function()
						return phoneInset
					end,
				},
				Players = { LocalPlayer = phonePlayer },
				UserInputService = {
					TouchEnabled = true,
					KeyboardEnabled = false,
					InputBegan = signal(),
				},
				TextChatService = {},
				CollectionService = {
					GetTagged = function()
						return {}
					end,
					GetInstanceAddedSignal = function()
						return signal()
					end,
				},
			},
			globals = {
				workspace = {
					CurrentCamera = camera,
					GetAttribute = function(_, name)
						return attributes[name]
					end,
				},
			},
			mocks = {
				HUD = {
					SetModal = function() end,
				},
			},
		})
		local UITheme = phoneLoader:load("StarterPlayer/StarterPlayerScripts/UITheme")
		local PhoneLogic = phoneLoader:shared("SawmillLogic")
		local Phone = phoneLoader:load("StarterPlayer/StarterPlayerScripts/SawmillController")
		Phone.Start()
		local gui = pg:FindFirstChild("SawmillCut")
		t.ok(gui, "the cut screen")
		local root = gui:FindFirstChild("Card")
		t.ok(root, "the card")
		-- The safe screen is the viewport minus the top inset. AbsolutePosition
		-- stays (0, 0), which is what the engine can report.
		gui.AbsolutePosition = Vector2.new(0, 0)
		gui.AbsoluteSize = Vector2.new(667, viewportH - inset)
		root.AbsolutePosition = Vector2.new(0, 0)
		root.AbsoluteSize = Vector2.new(10, 10)
		Phone._open()
		root.Position = UDim2.fromOffset(0, viewportH)
		local watched = signals[gui]
		t.ok(watched and watched.AbsoluteSize, "the card listens for its screen size")
		watched.AbsoluteSize:Fire()
		local size = gui.AbsoluteSize
		local scale = UITheme.ScaleFor(size, true, false)
		local _, cardH = PhoneLogic.CardSize(false)
		local onScreenBottom = phoneInset.Y + root.Position.Y.Offset + cardH * scale
		local hotbar = viewportH - UITheme.Bottom()
		t.ok(
			onScreenBottom <= hotbar + 1e-4,
			"on-screen bottom " .. tostring(onScreenBottom) .. " hotbar " .. tostring(hotbar)
		)
	end)
end
