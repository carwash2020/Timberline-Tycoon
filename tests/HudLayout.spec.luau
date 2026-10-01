--!nocheck
-- The HUD's geometry (StarterPlayerScripts/HudLayout): the side buttons'
-- columns and the shop panel kept clear of the cash row, at the screen
-- sizes the layout has to work on.
return function(t)
	local Vector2 = t.roblox.Vector2
	local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")

	local GAP = 8
	local PHONE_BUTTON = Vector2.new(100, 39) -- HUD.layoutSide on a phone (36 + the 3 px edge)
	local function buttons(n, size)
		local out = {}
		for i = 1, n do
			out[i] = size
		end
		return out
	end
	local function v(x, y)
		return Vector2.new(x, y)
	end

	t.test("side buttons stack up from the corner while they fit", function()
		local spots = HudLayout.Stack(buttons(3, v(110, 43)), 400, GAP)
		-- Top to bottom: the last one sits in the corner.
		t.eq(spots, { v(0, 102), v(0, 51), v(0, 0) })
	end)

	t.test("what doesn't fit starts a column to the left, bottom first", function()
		-- 844 x 390 phone with the 58 px top bar: under the Daily Goals
		-- button (y 152) + 8, down to 24 above the jump button (y 300).
		local room = (300 - 24) - (152 + 8)
		local spots = HudLayout.Stack(buttons(4, PHONE_BUTTON), room, GAP)
		t.eq(spots, { v(108, 47), v(108, 0), v(0, 47), v(0, 0) })
		for _, spot in ipairs(spots) do
			t.ok(spot.Y + PHONE_BUTTON.Y <= room, "every button ends under the corner")
		end
		-- Three: the first one alone on the left.
		t.eq(HudLayout.Stack(buttons(3, PHONE_BUTTON), room, GAP), { v(108, 0), v(0, 47), v(0, 0) })
	end)

	t.test("a column is as wide as its widest button", function()
		-- A gamepad: buttons with a glyph are wider. Two to a column.
		local b, wide = v(110, 43), v(150, 43)
		local spots = HudLayout.Stack({ b, b, wide, b, b }, 100, GAP)
		t.eq(spots, { v(118 + 150 + 8, 0), v(118, 51), v(118, 0), v(0, 51), v(0, 0) })
	end)

	t.test("a column always takes one button, even with no room", function()
		t.eq(HudLayout.Stack(buttons(2, PHONE_BUTTON), 10, GAP), { v(108, 0), v(0, 0) })
		t.eq(HudLayout.Stack({}, 100, GAP), {})
	end)

	local PANEL = v(560, 540)
	-- The shop's area on a screen (offsets): top 44, bottom 8, sides 12.
	local function areaOn(w, h)
		return { left = 12, top = 44, right = w - 12, bottom = h - 8 }
	end
	-- HUD's cash row ([pops][♪][plaque], 226 wide, 49 tall) at the right
	-- margin, 8 under the top bar, in the shop screen's offsets.
	local function cashRow(w, inset, margin)
		return { left = w - margin - 226, top = inset + 8, right = w - margin, bottom = inset + 57 }
	end

	t.test("a spilled column is lifted clear of the bottom-centre bar when there's room", function()
		-- 844 x 390: corner at (832, 276), the bar band x 246..598 from y 210.
		local band = { left = 246, right = 598, top = 210, bottom = 390 }
		local sizes = buttons(3, PHONE_BUTTON)
		local spots = HudLayout.Stack(sizes, 100, GAP) -- two to a column
		t.eq(spots[1], v(108, 0), "the first button spills left")
		local lifted = HudLayout.LiftClear(spots, sizes, v(832, 276), band, 100, GAP)
		-- That column's right edge is 724, clear of the band: it stays.
		t.eq(lifted, spots)
		-- A narrower screen, where it does reach the band, with room above.
		local narrow = { left = 163, right = 503, top = 181, bottom = 375 }
		local lifted2 = HudLayout.LiftClear(spots, sizes, v(655, 285), narrow, 60, GAP)
		local bottom = 285 - lifted2[1].Y
		t.ok(bottom <= narrow.top - GAP, "lifted above the bar")
		t.eq(lifted2[2], spots[2], "the corner column doesn't move")
		-- No room above it: it stays (the bar's screen draws over it).
		t.eq(HudLayout.LiftClear(spots, sizes, v(655, 285), narrow, 160, GAP), spots)
	end)

	t.test("on a phone the shop panel moves left of the cash row", function()
		for _, screen in ipairs({ v(844, 390), v(667, 375) }) do
			for _, inset in ipairs({ 36, 58 }) do
				local row = cashRow(screen.X, inset, 12)
				local area = HudLayout.ClearOf(areaOn(screen.X, screen.Y), PANEL, row, 8, 400)
				local panel = HudLayout.Centred(area, PANEL)
				t.ok(panel.right <= row.left - 8, "clear of the row")
				t.ok(panel.right - panel.left >= 400, "still wide enough")
				t.eq(panel.top, 44, "keeps its height")
			end
		end
		-- 844 wide: the full 560, just shifted.
		local area = HudLayout.ClearOf(areaOn(844, 390), PANEL, cashRow(844, 58, 12), 8, 400)
		local panel = HudLayout.Centred(area, PANEL)
		t.eq(panel.right - panel.left, 560)
	end)

	t.test("on a monitor or a TV the centred panel already misses the row", function()
		-- 1920 x 1080 at 1.25x and a TV at 1.5x, in offsets.
		local desktop = areaOn(1536, 864)
		t.eq(HudLayout.ClearOf(desktop, PANEL, cashRow(1536, 46.4, 12), 8, 400), desktop)
		local tv = areaOn(1280, 720)
		t.eq(HudLayout.ClearOf(tv, PANEL, cashRow(1280, 38.7, 64), 8, 400), tv)
	end)

	t.test("too narrow beside the row: the panel starts under it instead", function()
		local row = cashRow(568, 58, 12)
		local area = HudLayout.ClearOf(areaOn(568, 320), PANEL, row, 8, 400)
		t.eq(area.top, row.bottom + 8)
		t.eq(area.right, 568 - 12)
	end)
end
