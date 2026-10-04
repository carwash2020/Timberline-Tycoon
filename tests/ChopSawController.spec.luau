--!nocheck
-- The length panel: D-pad, A, B, and the plus button selected on open.
return function(t)
	local Enum = t.roblox.Enum
	local Vector2 = t.roblox.Vector2
	local UDim2 = t.roblox.UDim2
	local modalLog = {}
	local gui = {
		IsTenFootInterface = function()
			return false
		end,
		TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
		GetGuiInset = function()
			return Vector2.zero, Vector2.zero
		end,
	}
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
		},
		globals = {
			workspace = { CurrentCamera = nil },
		},
		mocks = {
			HUD = {
				SetModal = function(rect)
					-- A bare nil doesn't stay in a Luau array, so wrap it.
					table.insert(modalLog, { rect = rect })
				end,
			},
		},
	})
	local Logic = loader:shared("ChopSawLogic")
	local Input = loader:shared("InputKit")
	local UITheme = loader:load("StarterPlayer/StarterPlayerScripts/UITheme")
	local Controller = loader:load("StarterPlayer/StarterPlayerScripts/ChopSawController")
	local fs = require("@lune/fs")

	t.test("opening the panel selects plus, and the pad changes length, cuts, and closes", function()
		local panel = Controller.BuildPanel(false)
		t.eq(panel.gui.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets)
		t.eq(panel.plus.Name, "LengthPlus")
		t.eq(panel.plus:GetAttribute("Axis"), "x")
		t.eq(panel.plus:GetAttribute("Dir"), 1)
		t.eq(panel.minus:GetAttribute("Dir"), -1)
		local face = Logic.PanelFace(false)
		t.eq(panel.plus.Size.X.Offset, face)
		t.eq(panel.plus.Size.Y.Offset, face)
		t.eq(Input.TouchOk(face), true)
		t.eq(panel.root.AnchorPoint, Vector2.new(0.5, 1))
		t.eq(panel.root.Position, UDim2.new(0.5, 0, 1, -(UITheme.Bottom() + Logic.AboveHotbarPx)))
		panel.root.AbsolutePosition = Vector2.new(173, 205)
		panel.root.AbsoluteSize = Vector2.new(320, 92)
		Controller._open(nil, panel)
		t.eq(gui.SelectedObject, panel.plus)
		t.eq(panel.gui.Enabled, true)
		local opened = modalLog[#modalLog].rect
		local at, size = panel.root.AbsolutePosition, panel.root.AbsoluteSize
		t.eq(opened.left, at.X)
		t.eq(opened.top, at.Y)
		t.eq(opened.right, at.X + size.X)
		t.eq(opened.bottom, at.Y + size.Y)
		local axis, dir = Controller.ApplyKey(Enum.KeyCode.DPadLeft)
		t.eq(axis, "x")
		t.eq(dir, -1)
		axis, dir = Controller.ApplyKey(Enum.KeyCode.DPadRight)
		t.eq(axis, "x")
		t.eq(dir, 1)
		axis, dir = Controller.ApplyKey(Enum.KeyCode.Left)
		t.eq(dir, -1)
		axis, dir = Controller.ApplyKey(Enum.KeyCode.Right)
		t.eq(dir, 1)
		t.eq(Controller.ApplyKey(Enum.KeyCode.ButtonA), "cut")
		t.eq(panel.gui.Enabled, false)
		t.eq(gui.SelectedObject, nil)
		Controller._open(nil, panel)
		t.eq(gui.SelectedObject, panel.plus)
		t.eq(Controller.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(panel.gui.Enabled, false)
		t.eq(gui.SelectedObject, nil)
		t.eq(modalLog[#modalLog].rect, nil)
		Controller._open(nil, panel)
		t.eq(Controller.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(panel.gui.Enabled, false)
		local tv = Controller.BuildPanel(true)
		t.eq(tv.plus.Size.X.Offset, Logic.PanelFace(true))
		t.ok(tv.plus.Size.X.Offset >= Input.MinTouchPx)
	end)

	t.test("the controller does not bind the HUD D-pad, and ± repeats while held", function()
		local source = fs.readFile("src/StarterPlayer/StarterPlayerScripts/ChopSawController.luau")
		t.eq(string.find(source, "Enum.KeyCode.DPad", 1, true), nil)
		t.ok(string.find(source, "ChopSawLogic.PadStep", 1, true))
		t.ok(string.find(source, "ChopSawLogic.Cuts", 1, true))
		t.ok(string.find(source, "ChopSawLogic.PanelCloses", 1, true))
		t.ok(string.find(source, "SelectedObject", 1, true))
		t.ok(string.find(source, "ChopSawLogic.HoldRepeat", 1, true))
		t.ok(string.find(source, "MouseButton1Down", 1, true))
		t.ok(string.find(source, "UITheme.Screen", 1, true))
		t.ok(string.find(source, "HUD.SetModal", 1, true))
		t.eq(Input.PlacerSafe(Logic.PanelBinds, true), true)
	end)
end
