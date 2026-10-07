--!nocheck
-- The homestead picker selects Claim on open and closes on B or Esc.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local fs = require("@lune/fs")
	local gui = { SelectedObject = nil }
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			TweenService = {},
			RunService = {},
		},
	})
	local Picker = loader:load("StarterPlayer/StarterPlayerScripts/PlotPickerUI")

	t.test("opening selects Claim, and B or Esc closes the picker", function()
		local claim = Instance.new("TextButton")
		claim.Name = "Claim"
		Picker._open(claim)
		t.eq(gui.SelectedObject, claim)
		t.eq(Picker.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		Picker._open(claim)
		t.eq(Picker.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotUI.luau")
		t.ok(string.find(src, "body.Selectable = false", 1, true), "the land panel does not eat the D-pad")
	end)
end
