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

	-- Final pass: the respawn handler waits for the humanoid; a close in that wait must not lock afterwards.
	t.test("a respawn that finishes after the picker closed does not lock the player", function()
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/PlotPickerUI.luau")
		local wait = string.find(src, 'char:WaitForChild("Humanoid", 5)', 1, true)
		local recheck = string.find(src, "if not open then", wait or 1, true)
		local lock = string.find(src, "\t\t\tlock()", wait or 1, true)
		t.ok(wait and recheck and lock and recheck < lock, "open is checked again before lock()")
		t.ok(string.find(src, "button.TextScaled = true", 1, true), "the narrow phone panel shrinks its labels")
	end)
end
