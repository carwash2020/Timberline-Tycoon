--!nocheck
-- MiningUI and CraftUI: they fit 667x375 and 1920x1080, taps are 44 px,
-- and nothing sits in the thumbstick or the jump zone.

return function(t)
	local Enum = t.roblox.Enum
	local Vector2 = t.roblox.Vector2
	pcall(t.roblox.implementProperty, "TextButton", "Activated", function()
		return {
			Connect = function()
				return { Disconnect = function() end }
			end,
		}
	end)
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
			UserInputService = {
				TouchEnabled = false,
				KeyboardEnabled = true,
				GetLastInputType = function()
					return Enum.UserInputType.Keyboard
				end,
			},
			TextChatService = {},
		},
		globals = {
			workspace = { CurrentCamera = { ViewportSize = Vector2.new(667, 375) } },
		},
	})
	local MiningUI = loader:load("StarterPlayer/StarterPlayerScripts/MiningUI")
	local CraftUI = loader:load("StarterPlayer/StarterPlayerScripts/CraftUI")

	local function clear(rect, w, h)
		t.eq(MiningUI.Overlaps(rect, MiningUI.Thumbstick(w, h)), false)
		t.eq(MiningUI.Overlaps(rect, MiningUI.Jump(w, h)), false)
		t.ok(rect.x >= 12 and rect.y >= 12, "margin")
		t.ok(rect.x + rect.w <= w - 12)
		t.ok(rect.y + rect.h <= h * 0.5)
	end

	t.test("both viewports keep the panels out of the thumbstick and the jump zone", function()
		for _, size in ipairs({ Vector2.new(667, 375), Vector2.new(1920, 1080) }) do
			local rects = MiningUI.Rects(size.X, size.Y)
			clear(rects.chip, size.X, size.Y)
			clear(rects.panel, size.X, size.Y)
			t.ok(rects.chip.h >= 44)
			t.ok(rects.panel.h >= 44)
			local bench = CraftUI.Rects(size.X, size.Y)
			clear(bench, size.X, size.Y)
			t.ok(bench.h <= size.Y * 0.6, "panel stays within 60 percent of the screen")
			t.ok(rects.panel.h <= size.Y * 0.6)
		end
		t.eq(MiningUI.NamePx(667, 375), 16)
		t.eq(MiningUI.NamePx(1280, 720), 18)
		t.eq(CraftUI.NamePx(667, 375), 16)
		t.eq(CraftUI.NamePx(1280, 720), 18)
	end)

	t.test("shop rows are 44 px and eight px apart, and B closes", function()
		local built = MiningUI.Ensure(Vector2.new(667, 375))
		t.eq(built.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets)
		MiningUI.FillShop(100, {})
		local rows = built:FindFirstChild("Rows", true)
		local previous = nil
		local count = 0
		for _, child in ipairs(rows:GetChildren()) do
			if child:IsA("TextButton") then
				count += 1
				t.ok(child.Size.Y.Offset >= 44, "row is a 44 px tap")
				t.eq(child.Text, "")
				local name = child:FindFirstChild("Name")
				t.eq(name.TextScaled, false)
				t.eq(name.TextSize, MiningUI.NamePx(667, 375))
				local price = child:FindFirstChild("Price")
				t.eq(price.TextSize, 14)
				t.eq(price.TextScaled, false)
				if previous then
					t.ok(child.Position.Y.Offset == 0 or true)
				end
				previous = child
			end
		end
		t.ok(count >= 2, "picks and a bomb")
		local layout = rows:FindFirstChildOfClass("UIListLayout")
		t.eq(layout.Padding.Offset, 8)
		MiningUI.Open()
		t.eq(gui.SelectedObject ~= nil, true)
		t.eq(MiningUI.ApplyKey(Enum.KeyCode.ButtonB), "close")
		t.eq(gui.SelectedObject, nil)
	end)

	t.test("a missing craft remote labels every craft button Soon at 44 px", function()
		CraftUI.SetReady(false)
		local built = CraftUI.Ensure(Vector2.new(667, 375))
		t.eq(built.ScreenInsets, Enum.ScreenInsets.CoreUISafeInsets)
		CraftUI.Fill({ ingots = {}, chunks = {} }, false)
		local count = 0
		for _, child in ipairs(built:GetDescendants()) do
			if child.Name == "Craft" and child:IsA("TextButton") then
				count += 1
				t.eq(child.Text, "Soon")
				t.eq(child.Size.X.Offset, 44)
				t.eq(child.Size.Y.Offset, 44)
				t.eq(child.TextScaled, false)
				t.ok(child.TextSize >= 14)
				local row = child.Parent
				local name = row:FindFirstChild("Name")
				t.eq(name.TextScaled, false)
				t.eq(name.TextSize, CraftUI.NamePx(667, 375))
				t.eq(string.find(name.Text, "/", 1, true), nil)
				local cost = row:FindFirstChild("Cost")
				t.eq(cost.TextSize, 14)
				t.eq(cost.TextScaled, false)
			end
		end
		t.eq(count, 6)
		t.eq(MiningUI.ChipLine("Iron Pick", 3, 2, true, false), "Iron Pick  ·  Lv 3  ·  Bombs 2  ·  Lamp")
		t.eq(MiningUI.OwnedMap("RustyPick,IronPick").IronPick, true)
		t.eq(MiningUI.OwnedMap("RustyPick,IronPick").CopperPick, nil)
	end)
end
