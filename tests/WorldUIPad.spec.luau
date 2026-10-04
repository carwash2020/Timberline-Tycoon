--!nocheck
-- The clock can take the pad. It is not selected just because it exists.
-- B or Esc clears it once it has focus.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local Vector2 = t.roblox.Vector2
	local gui = {
		SelectedObject = nil,
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
			Lighting = { ClockTime = 14 },
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
		},
		mocks = {
			HUD = {
				BesideCash = function()
					return Instance.new("Frame")
				end,
				UnderCash = function()
					return nil
				end,
				Toast = function() end,
			},
		},
	})
	local World = loader:load("StarterPlayer/StarterPlayerScripts/WorldUI")

	t.test("B or Esc clears the clock only after it was focused", function()
		local parent = Instance.new("Frame")
		local clock = World.MakeClock(parent, Vector2.new(100, 30), 16)
		t.eq(clock.ClassName, "TextButton")
		t.eq(clock.Selectable, true)
		t.eq(World.ApplyKey(Enum.KeyCode.ButtonB), nil)
		t.eq(gui.SelectedObject, nil)
		World._open(clock)
		t.eq(gui.SelectedObject, clock)
		t.eq(World.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		World._open(clock)
		t.eq(World.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
	end)
end
