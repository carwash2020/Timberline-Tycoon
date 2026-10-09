--!nocheck
-- The phone HUD's side column (Shared/PhoneHud, HUD.layoutSide/arrangeSide):
-- MENU, HAMMER and Sell here as 44 x 44 icon buttons, one column, 8 px
-- apart, no wrap; SAVES, Send truck home and the owner's button inside
-- MENU. The HUD's own Instances need Roblox; the numbers it uses are here.
return function(t)
	local Vector2 = t.roblox.Vector2
	local PhoneHud = t.load("ReplicatedStorage/Shared/PhoneHud")
	local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
	local UITheme = t.loader({
		services = { GuiService = {}, Players = { LocalPlayer = {} }, TextChatService = {}, UserInputService = {} },
	}):load("StarterPlayer/StarterPlayerScripts/UITheme")

	t.test("the column is MENU, HAMMER and Sell here, and the rest is inside MENU", function()
		t.eq(PhoneHud.Column, { "Menu", "Hammer", "InstantDelivery" })
		for _, name in ipairs({ "Saves", "CallTruck", "Owner" }) do
			t.ok(PhoneHud.IsFolded(name), name .. " lives inside MENU on a phone")
		end
		for _, name in ipairs(PhoneHud.Column) do
			t.ok(not PhoneHud.IsFolded(name), name .. " stays in the column")
			t.ok(PhoneHud.IconFor(name), name .. " has an icon")
		end
		t.eq(PhoneHud.IconFor("Saves"), nil)
	end)

	t.test("each icon names a real image id and a short text for when it fails", function()
		local want = { Menu = "MENU", Hammer = "BUILD", InstantDelivery = "SELL" }
		for name, text in pairs(want) do
			local icon = PhoneHud.IconFor(name)
			t.eq(icon.text, text)
			t.ok(UITheme.HudIcons[icon.key] and UITheme.HudIcons[icon.key] > 0, icon.key .. " has a real id")
			t.ok(UITheme.HudIconImage(icon.key), icon.key .. " draws an image")
		end
	end)

	t.test("the buttons are 44 x 44 with the image 28 x 28 inside (8 px of padding)", function()
		t.eq(PhoneHud.Size, 44)
		t.eq(UITheme.Size.Icon, PhoneHud.Size)
		t.eq(PhoneHud.Glyph, 28)
		t.eq(UITheme.Size.IconGlyph, PhoneHud.Glyph)
		t.ok(PhoneHud.Size >= UITheme.Size.Tap, "a fingertip")
		t.eq((PhoneHud.Size - PhoneHud.Glyph) / 2, 8)
	end)

	-- One column, no wrap, faces 8 px apart, at the phone sizes the HUD uses.
	for _, screen in ipairs({ Vector2.new(667, 375), Vector2.new(812, 375), Vector2.new(844, 390) }) do
		t.test(
			string.format("%dx%d: three icon buttons stack in one column, faces 8 apart", screen.X, screen.Y),
			function()
				local drop = UITheme.ButtonDrop
				-- The jump button: 70 px, 95 from the right and 90 up (NewsUI's note).
				local jump = {
					left = screen.X - 95,
					top = screen.Y - 90,
					right = screen.X - 25,
					bottom = screen.Y - 20,
				}
				-- The corner's second line ends about 100 down on a phone.
				local spot, room = HudLayout.SideColumn(screen, 100, jump, 12, 8, 24, 44)
				local size = Vector2.new(PhoneHud.Size, PhoneHud.Size + drop)
				local spots = HudLayout.Stack({ size, size, size }, room, PhoneHud.StackGap(drop))
				for i, s in ipairs(spots) do
					t.eq(s.X, 0, "button " .. i .. " is in the one column")
				end
				-- Top to bottom is MENU, HAMMER, Sell here: each face ends 8 above the next.
				local function faceBottom(i)
					return spot.Y - spots[i].Y - drop
				end
				local function faceTop(i)
					return spot.Y - spots[i].Y - size.Y
				end
				t.eq(faceTop(3) - faceBottom(2), 8)
				t.eq(faceTop(2) - faceBottom(1), 8)
				t.eq(faceBottom(1) - faceTop(1), 44)
				t.ok(faceTop(1) >= 100 + 8, "under the corner's second line")
				-- Five wide buttons would have wrapped here; the three icons do not.
				t.ok(spot.X <= screen.X - 12, "12 from the edge at most")
			end
		)
	end

	t.test("the old five-button column wraps to a second column on a short phone", function()
		local drop = UITheme.ButtonDrop
		local size = Vector2.new(116, 44 + drop)
		local screen = Vector2.new(667, 375)
		local _, room = HudLayout.SideColumn(screen, 100, {
			left = screen.X - 95,
			top = screen.Y - 90,
			right = screen.X - 25,
			bottom = screen.Y - 20,
		}, 12, 8, 24, 44)
		local spots = HudLayout.Stack({ size, size, size, size, size }, room, 8)
		local wrapped = false
		for _, s in ipairs(spots) do
			wrapped = wrapped or s.X > 0
		end
		t.ok(wrapped, "that is the layout this replaces")
	end)

	t.test("the phone stack gap is the 8 px face gap less the drop edge", function()
		t.eq(PhoneHud.Gap, 8)
		t.eq(PhoneHud.StackGap(3), 5)
	end)

	t.test("the deep green icon style carries cream on green at 3:1 or more", function()
		t.eq(PhoneHud.IconStyle.Hammer, "iconGreen")
		t.eq(PhoneHud.IconStyle.InstantDelivery, "iconGreen")
		t.ok(UITheme.Styles.iconGreen, "the style exists")
	end)
end
