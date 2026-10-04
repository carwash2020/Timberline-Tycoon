--!nocheck
-- The mill's cut panel: a prompt opens it, the buttons clear a phone,
-- and the D-pad (plus arrows) changes X and Y without taking the HUD's keys.
return function(t)
	local Enum = t.roblox.Enum
	local loader = t.loader({
		services = {
			GuiService = {},
			Players = {},
			UserInputService = {},
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
	end)
end
