--!nocheck
-- The field guide selects its first row on open and closes on B or Esc.
return function(t)
	local Enum = t.roblox.Enum
	local Instance = t.roblox.Instance
	local gui = { SelectedObject = nil }
	local closed = false
	local loader = t.loader({
		services = {
			GuiService = gui,
			Players = { LocalPlayer = {} },
			UserInputService = { TouchEnabled = false, KeyboardEnabled = true },
			TextChatService = {},
		},
		mocks = {
			HUD = {
				PadShortcut = function() end,
				PadGlyph = function()
					return Instance.new("Frame")
				end,
				Toast = function() end,
			},
			ShopUI = {
				Close = function()
					closed = true
				end,
				OpenCustom = function() end,
				FirstFace = function()
					return nil
				end,
				Refresh = function() end,
			},
		},
	})
	local Guide = loader:load("StarterPlayer/StarterPlayerScripts/FieldGuideUI")

	t.test("opening selects the first row, and B or Esc closes the guide", function()
		local row = Instance.new("TextButton")
		row.Name = "Wood"
		Guide._open(row)
		t.eq(gui.SelectedObject, row)
		t.eq(Guide.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
		t.eq(closed, true)
		Guide._open(row)
		t.eq(Guide.ApplyKey(Enum.KeyCode.Escape), "close")
		t.eq(gui.SelectedObject, nil)
	end)
end
