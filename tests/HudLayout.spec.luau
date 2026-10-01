--!nocheck
-- The HUD's geometry (StarterPlayerScripts/HudLayout): the side buttons'
-- columns, the shop panel kept clear of the cash row, and the toast lane
-- kept clear of the corner and the tutorial tracker, at the screen sizes
-- the layout has to work on.
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

	-- The toast lane. Sizes as the HUD builds them, in the HUD screen's
	-- offsets (which mind the top bar and a phone's safe-area insets).
	local TOAST_W, LANE_MIN = 280, 240 -- HUD's widest toast, and the narrowest band for a lane at the top
	local CASH, STORE, CLOCK, POUCH, DAILY, DAILY_STREAK = 226, 90, 100, 84, 200, 300
	local TRACKER, SPEECH, GUIDE = 92, 6 + 80, 37 -- the tracker, Murph's card under it, the Field Guide button
	local function widths(...)
		local sum, n = 0, 0
		for _, w in ipairs({ ... }) do
			sum += w
			n += 1
		end
		return sum + 8 * math.max(0, n - 1)
	end
	-- The corner: line 1 (the cash row, 49 tall, and what's beside it) at
	-- y 8, line 2 (30 tall) 7 under it, right-aligned at the margin.
	local function cornerOf(screenW, line1, line2, margin)
		margin = margin or 12
		return {
			left = screenW - margin - math.max(line1, line2),
			top = 8,
			right = screenW - margin,
			bottom = if line2 > 0 then 8 + 49 + 7 + 30 else 8 + 49,
		}
	end
	-- The left column: 280 wide (QuestUI's tutorial frame), from `top`.
	local function columnOf(top, height, margin)
		margin = margin or 12
		return { left = margin, top = top, right = margin + 280, bottom = top + height }
	end
	local function clear(a, b, gap)
		return a.right + gap <= b.left or b.right + gap <= a.left or a.bottom + gap <= b.top or b.bottom + gap <= a.top
	end
	local function checkLane(name, screen, corner, column, lane)
		t.ok(clear(lane, corner, 8), name .. ": the lane is clear of the corner")
		if column then
			t.ok(clear(lane, column, 8), name .. ": the lane is clear of the tracker")
		end
		t.ok(lane.left >= 0 and lane.right <= screen.X, name .. ": on screen")
		t.ok(lane.right - lane.left >= LANE_MIN, name .. ": wide enough for a toast")
		t.ok(lane.top >= 0 and lane.top < lane.bottom, name .. ": room to stack down")
	end

	t.test("on a 667 x 375 phone today's top-centre lane covers the clock; the lane goes under the tracker", function()
		local screen = v(667, 375 - 58)
		-- Before: the clock beside the cash, toasts centred at the top.
		local clock = { left = 667 - 12 - widths(CLOCK, CASH), top = 8, right = 667 - 12 - CASH - 8, bottom = 38 }
		local today = { left = 667 / 2 - 140, top = 8, right = 667 / 2 + 140, bottom = 8 + 3 * 40 }
		t.ok(not clear(today, clock, 0), "the evidence: today's lane (x 193-473) covers the clock")
		-- Even with the clock still there, the lane now misses it.
		local withClock = cornerOf(667, widths(CLOCK, CASH), widths(POUCH, DAILY))
		local tracker = columnOf(60, TRACKER)
		local lane = HudLayout.ToastLane(screen, withClock, tracker, TOAST_W, LANE_MIN, screen.Y - 12)
		checkLane("667 clock on line 1", screen, withClock, tracker, lane)
		t.ok(clear(lane, clock, 8), "clear of the clock")
		t.eq(lane.under, true)
	end)

	t.test("667 x 375 (iPhone SE): under the tracker at its width, two toasts, one when Murph's card is up", function()
		for _, inset in ipairs({ 36, 58 }) do
			local screen = v(667, 375 - inset)
			-- In the tutorial the clock is off the corner (ClockLine).
			local corner = cornerOf(667, CASH, widths(POUCH, DAILY))
			local tracker = columnOf(60, TRACKER)
			local lane = HudLayout.ToastLane(screen, corner, tracker, TOAST_W, LANE_MIN, screen.Y - 12)
			checkLane("SE " .. inset, screen, corner, tracker, lane)
			t.eq(lane.under, true)
			t.eq(lane.left, tracker.left, "lined up with the tracker")
			t.eq(lane.right - lane.left, 280, "at its width")
			t.eq(lane.top, tracker.bottom + 8)
			t.eq(lane.max, 2)
			local talking = columnOf(60, TRACKER + SPEECH)
			local low = HudLayout.ToastLane(screen, corner, talking, TOAST_W, LANE_MIN, screen.Y - 12)
			checkLane("SE " .. inset .. " with Murph", screen, corner, talking, low)
			t.eq(low.max, 1, "no room for two above the bottom edge")
		end
		-- After the tutorial: the clock on line 2, the Field Guide button up top.
		local screen = v(667, 375 - 58)
		local corner = cornerOf(667, CASH, widths(CLOCK, POUCH, DAILY_STREAK))
		local column = columnOf(60, GUIDE + 6)
		local lane = HudLayout.ToastLane(screen, corner, column, TOAST_W, LANE_MIN, screen.Y - 12)
		checkLane("SE after the tutorial", screen, corner, column, lane)
		t.eq(lane.max, 2)
	end)

	t.test("844 x 390 with 47/47/21 insets (iPhone 14 Pro): under the tracker", function()
		local screen = v(844 - 47 - 47, 390 - 58 - 21)
		local cases = {
			{ "tutorial", cornerOf(screen.X, CASH, widths(POUCH, DAILY)), columnOf(60, TRACKER) },
			{ "tutorial, Murph", cornerOf(screen.X, CASH, widths(POUCH, DAILY)), columnOf(60, TRACKER + SPEECH) },
			{
				"after",
				cornerOf(screen.X, widths(STORE, CASH), widths(CLOCK, POUCH, DAILY_STREAK)),
				columnOf(60, GUIDE + 6),
			},
		}
		for _, case in ipairs(cases) do
			local name, corner, column = case[1], case[2], case[3]
			local lane = HudLayout.ToastLane(screen, corner, column, TOAST_W, LANE_MIN, screen.Y - 12)
			checkLane("14 Pro " .. name, screen, corner, column, lane)
			t.eq(lane.under, true, name)
			t.ok(lane.max >= 1 and lane.max <= 2, name .. ": at most two")
		end
	end)

	t.test("computers and TVs: centred between the column and the corner, at most 280 wide, three toasts", function()
		local lines1 = widths(STORE, CLOCK, CASH)
		local cases = {
			-- name, screen (offsets), line 2, column top (under the chat), margin
			{ "1024 x 768 with STORE", v(1024, 768 - 58), widths(POUCH, DAILY_STREAK), 250, 12 },
			{ "1366 x 768", v(1366, 768 - 58), widths(POUCH, DAILY), 250, 12 },
			{ "1920 x 1080 (1.25x)", v(1536, (1080 - 58) / 1.25), widths(POUCH, DAILY), 0.3 * 817, 12 },
			{ "a TV (1.5x)", v(1280, (1080 - 58) / 1.5), widths(POUCH, DAILY), 0.3 * 681, 64 },
		}
		for _, case in ipairs(cases) do
			local name, screen, line2, columnTop, margin = case[1], case[2], case[3], case[4], case[5]
			local corner = cornerOf(screen.X, lines1, line2, margin)
			for _, column in ipairs({ columnOf(columnTop, TRACKER, margin), columnOf(8, TRACKER + SPEECH, margin) }) do
				local lane = HudLayout.ToastLane(screen, corner, column, TOAST_W, LANE_MIN, screen.Y - 12)
				checkLane(name, screen, corner, column, lane)
				t.eq(lane.under, false, name)
				t.eq(lane.top, 8, name .. ": at the top")
				t.eq(lane.max, 3, name)
				t.ok(lane.right - lane.left <= 280, name .. ": at most 280")
				-- Centred in the band between them.
				local leftGap, rightGap = lane.left - column.right, corner.left - lane.right
				t.ok(math.abs(leftGap - rightGap) < 1e-6, name .. ": centred")
			end
		end
		-- 1024 with STORE: the band is 272 wide, and the lane fills it.
		local corner = cornerOf(1024, lines1, widths(POUCH, DAILY))
		local lane = HudLayout.ToastLane(v(1024, 710), corner, columnOf(250, TRACKER), TOAST_W, LANE_MIN)
		t.eq({ lane.left, lane.right }, { 300, 572 })
		-- HUD passes the column with Roblox's chat window above it: a chat
		-- 400 wide leaves too narrow a band, so the toasts go under the column.
		local withChat = { left = 8, top = 0, right = 408, bottom = 250 + TRACKER }
		local under = HudLayout.ToastLane(v(1024, 710), corner, withChat, TOAST_W, LANE_MIN, 698)
		checkLane("1024 with a wide chat", v(1024, 710), corner, withChat, under)
		t.eq(under.under, true)
	end)

	t.test("no column yet, and a column too short to clear the corner", function()
		-- Desktop with no column: centred between the left margin and the corner.
		local desk = cornerOf(1366, widths(STORE, CLOCK, CASH), 0)
		local lane = HudLayout.ToastLane(v(1366, 710), desk, nil, TOAST_W, LANE_MIN)
		checkLane("desktop, no column", v(1366, 710), desk, nil, lane)
		t.eq(lane.under, false)
		-- A phone with no column: the band from the left margin may be wide enough...
		local phone = cornerOf(667, CASH, widths(POUCH, DAILY))
		local top = HudLayout.ToastLane(v(667, 317), phone, nil, TOAST_W, LANE_MIN)
		checkLane("phone, no column", v(667, 317), phone, nil, top)
		t.eq(top.under, false)
		-- ... and where it isn't, the lane starts under the corner at the margin.
		local wide = cornerOf(667, CASH, widths(CLOCK, POUCH, DAILY_STREAK))
		local low = HudLayout.ToastLane(v(667, 317), wide, nil, TOAST_W, LANE_MIN)
		checkLane("phone, no column, wide corner", v(667, 317), wide, nil, low)
		t.eq({ low.left, low.top }, { 12, wide.bottom + 8 })
		-- An empty column beside a corner that leaves less than 240: under the corner.
		local empty = columnOf(60, 0)
		local under = HudLayout.ToastLane(v(667, 317), wide, empty, TOAST_W, LANE_MIN)
		checkLane("phone, empty column", v(667, 317), wide, empty, under)
		t.eq(under.top, wide.bottom + 8)
		-- ... or, with room for 240, ends left of it.
		local mid = cornerOf(667, CASH, widths(POUCH, DAILY, 60))
		local beside = HudLayout.ToastLane(v(667, 317), mid, empty, TOAST_W, LANE_MIN)
		checkLane("phone, empty column, mid corner", v(667, 317), mid, empty, beside)
		t.eq(beside.top, 68)
		t.eq(beside.right, mid.left - 8)
	end)

	t.test("the clock: beside the cash on a computer, line 2 on a phone, hidden there in the tutorial", function()
		t.eq(HudLayout.ClockLine(false, 0), "beside")
		t.eq(HudLayout.ClockLine(false, 3), "beside")
		t.eq(HudLayout.ClockLine(true, 0), "under")
		t.eq(HudLayout.ClockLine(true, 1), "none")
		t.eq(HudLayout.ClockLine(true, 7), "none")
	end)
end
