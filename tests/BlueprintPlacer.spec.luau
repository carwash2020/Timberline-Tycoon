--!nocheck
-- Placing rotates on D-pad right, sinks that key, and puts prompts back
-- to whatever they were. Settings does not open while a piece is placing.
return function(t)
	local Enum = t.roblox.Enum
	local fs = require("@lune/fs")
	local loader = t.loader({
		services = {
			GuiService = {
				IsTenFootInterface = function()
					return false
				end,
				TopbarInset = t.roblox.Rect.new(0, 0, 0, 0),
				GetGuiInset = function()
					return t.roblox.Vector2.zero, t.roblox.Vector2.zero
				end,
			},
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			ContextActionService = {},
			ProximityPromptService = { Enabled = true },
			RunService = {},
			SoundService = {},
			Debris = {},
		},
		mocks = {
			HUD = {},
			CameraShake = {},
			Quality = {},
		},
	})
	local Placer = loader:load("StarterPlayer/StarterPlayerScripts/BlueprintPlacer")
	local Settings = loader:load("StarterPlayer/StarterPlayerScripts/SettingsUI")

	t.test("DPadRight rotates the piece and does not open Settings", function()
		t.eq(Placer.NextRot(0), 1)
		t.eq(Placer.NextRot(3), 0)
		t.eq(Placer.RotatePriority(), Enum.ContextActionPriority.High.Value + 100)
		t.eq(Settings.OpensOnPad(true, true), false)
		t.eq(Settings.OpensOnPad(true, false), true)
		t.eq(Settings.OpensOnPad(false, false), false)
		local src = fs.readFile("src/StarterPlayer/StarterPlayerScripts/BlueprintPlacer.luau")
		t.ok(string.find(src, "BindActionAtPriority", 1, true))
		t.ok(string.find(src, "Enum.KeyCode.DPadRight", 1, true))
		t.ok(string.find(src, 'PromptSwitch.Hold("placer")', 1, true))
		t.ok(string.find(src, 'PromptSwitch.Release("placer")', 1, true))
		t.ok(string.find(src, "humanoid.Died:Connect", 1, true))
		local added = string.match(src, "char%.ChildAdded:Connect%(function%(child: Instance%)(.-)\n\t\tend%)")
		t.ok(added, "a tool arriving while placing")
		t.ok(string.find(added, "BlueprintPlacer.Stop()", 1, true), "stops at once")
		t.eq(string.find(added, "Unequipped", 1, true), nil)
		t.eq(string.find(src, "ButtonX", 1, true), nil)
		local settings = fs.readFile("src/StarterPlayer/StarterPlayerScripts/SettingsUI.luau")
		t.ok(string.find(settings, "BlueprintPlacer.Active()", 1, true))
	end)
end
