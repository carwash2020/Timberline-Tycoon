--!nocheck
-- The figure stamp selects Dismiss. The Elder marker is 14 px, 18 on a TV.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local gui = {
		SelectedObject = nil,
		IsTenFootInterface = function()
			return false
		end,
	}
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
			TweenService = {},
			SoundService = {},
			Debris = {},
		},
		globals = {
			workspace = Instance.new("Folder"),
		},
		mocks = {
			HUD = { Toast = function() end },
			CameraShake = { Shake = function() end },
		},
	})
	local Forest = loader:load("StarterPlayer/StarterPlayerScripts/ForestUI")

	t.test("the stamp selects Dismiss, and the Elder marker grows on a TV", function()
		local dismiss = Instance.new("TextButton")
		dismiss.Name = "Dismiss"
		Forest._open(dismiss)
		t.eq(gui.SelectedObject, dismiss)
		t.eq(Forest.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		Forest._open(dismiss)
		t.eq(Forest.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
		t.eq(Forest.ElderTextPx(false), 14)
		t.eq(Forest.ElderTextPx(true), 18)
		local _, hand = Forest.MakeElderMarker(false)
		local _, tv = Forest.MakeElderMarker(true)
		t.eq(hand.TextSize, 14)
		t.eq(tv.TextSize, 18)
	end)
end
