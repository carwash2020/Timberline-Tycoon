--!nocheck
-- Daily goals: opening selects Close, and B or Esc clears it.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local gui = { SelectedObject = nil }
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
		},
		mocks = {
			HUD = {
				Popup = function() end,
				UnderCash = function()
					return nil
				end,
				PadShortcut = function() end,
				PadGlyph = function()
					return Instance.new("Frame")
				end,
			},
		},
	})
	local DailyUI = loader:load("StarterPlayer/StarterPlayerScripts/DailyUI")

	t.test("opening selects Close, and B or Esc closes the goals", function()
		local close = Instance.new("TextButton")
		close.Name = "Close"
		close.Size = t.roblox.UDim2.fromOffset(44, 44)
		t.ok(close.Size.X.Offset >= 44 and close.Size.Y.Offset >= 44)
		DailyUI._open(close)
		t.eq(gui.SelectedObject, close)
		t.eq(DailyUI.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		DailyUI._open(close)
		t.eq(DailyUI.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
	end)
end
