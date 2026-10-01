--!nocheck
-- The HUD's geometry (StarterPlayerScripts/HudLayout): the side buttons'
-- columns, the shop panel kept clear of the cash row, and the toast lane
-- kept clear of the corner and the tutorial tracker, at the screen sizes
-- the layout has to work on.
return function(t)
	local Vector2 = t.roblox.Vector2
	local HudLayout = t.load("StarterPlayer/StarterPlayerScripts/HudLayout")
	-- The sizes the screens build with (UITheme.Sizes), phone and desktop.
	local UITheme = t.loader({
		services = { GuiService = {}, Players = { LocalPlayer = {} }, TextChatService = {}, UserInputService = {} },
	}):load("StarterPlayer/StarterPlayerScripts/UITheme")
	local PHONE, DESK = UITheme.Sizes.phone, UITheme.Sizes.desktop

	local GAP = 8
	local EDGE = 3 -- a UITheme.Button's drop edge, under its face
	-- HUD.layoutSide on a phone: 116 x 44, and the edge.
	local PHONE_BUTTON = Vector2.new(PHONE.SideButton.size.X, PHONE.SideButton.size.Y + EDGE)
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
		-- button (58 + 8 + 49 + 7 + its 36 = y 158) + 8, down to 24 above the
		-- jump button (y 300).
		local room = (300 - 24) - (158 + 8)
		t.eq(PHONE_BUTTON, v(116, 47), "a phone's side button and its edge")
		local spots = HudLayout.Stack(buttons(4, PHONE_BUTTON), room, GAP)
		t.eq(spots, { v(124, 55), v(124, 0), v(0, 55), v(0, 0) })
		for _, spot in ipairs(spots) do
			t.ok(spot.Y + PHONE_BUTTON.Y <= room, "every button ends under the corner")
		end
		-- Three: the first one alone on the left.
		t.eq(HudLayout.Stack(buttons(3, PHONE_BUTTON), room, GAP), { v(124, 0), v(0, 55), v(0, 0) })
	end)

	t.test("a column is as wide as its widest button", function()
		-- A gamepad: buttons with a glyph are wider. Two to a column.
		local b, wide = v(110, 43), v(150, 43)
		local spots = HudLayout.Stack({ b, b, wide, b, b }, 100, GAP)
		t.eq(spots, { v(118 + 150 + 8, 0), v(118, 51), v(118, 0), v(0, 51), v(0, 0) })
	end)

	t.test("a column always takes one button, even with no room", function()
		t.eq(HudLayout.Stack(buttons(2, PHONE_BUTTON), 10, GAP), { v(124, 0), v(0, 0) })
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
		-- 926 x 428: corner at (914, 314), the bar band x 287..639 from y 248.
		local wideBand = { left = 287, right = 639, top = 248, bottom = 428 }
		local sizes = buttons(3, PHONE_BUTTON)
		local spots = HudLayout.Stack(sizes, 110, GAP) -- two to a column
		t.eq(spots[1], v(124, 0), "the first button spills left")
		local lifted = HudLayout.LiftClear(spots, sizes, v(914, 314), wideBand, 100, GAP)
		-- That column's left edge is 674, clear of the band: it stays.
		t.eq(lifted, spots)
		-- 844 x 390: corner at (832, 276), the band x 246..598 from y 210.
		-- The spilled column (x 592..708) reaches it, and there's room above.
		local band = { left = 246, right = 598, top = 210, bottom = 390 }
		local up = HudLayout.LiftClear(spots, sizes, v(832, 276), band, 100, GAP)
		t.ok(276 - up[1].Y <= band.top - GAP, "844: lifted above the bar")
		t.eq(up[2], spots[2], "844: the corner column doesn't move")
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
	-- The tracker, Murph's card under it (a line or so taller at a phone's
	-- 14 px), the Field Guide button (a fingertip tall on a phone).
	local TRACKER, SPEECH, GUIDE = 92, 6 + 100, PHONE.FieldGuide.size.Y + EDGE
	local LINE2, PHONE_LINE2 = DESK.DailyButton.size.Y, PHONE.DailyButton.size.Y -- the corner's second line: its pills
	local function widths(...)
		local sum, n = 0, 0
		for _, w in ipairs({ ... }) do
			sum += w
			n += 1
		end
		return sum + 8 * math.max(0, n - 1)
	end
	-- The corner: line 1 (the cash row, 49 tall, and what's beside it) at
	-- y 8, line 2 (30 tall, 36 on a phone: `line2H`) 7 under it,
	-- right-aligned at the margin.
	local function cornerOf(screenW, line1, line2, margin, line2H)
		margin = margin or 12
		return {
			left = screenW - margin - math.max(line1, line2),
			top = 8,
			right = screenW - margin,
			bottom = if line2 > 0 then 8 + 49 + 7 + (line2H or LINE2) else 8 + 49,
		}
	end
	local function phoneCorner(screenW, line1, line2)
		return cornerOf(screenW, line1, line2, 12, PHONE_LINE2)
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
		local withClock = phoneCorner(667, widths(CLOCK, CASH), widths(POUCH, DAILY))
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
			local corner = phoneCorner(667, CASH, widths(POUCH, DAILY))
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
		local corner = phoneCorner(667, CASH, widths(CLOCK, POUCH, DAILY_STREAK))
		local column = columnOf(60, GUIDE + 6)
		local lane = HudLayout.ToastLane(screen, corner, column, TOAST_W, LANE_MIN, screen.Y - 12)
		checkLane("SE after the tutorial", screen, corner, column, lane)
		t.eq(lane.max, 2)
	end)

	t.test("844 x 390 with 47/47/21 insets (iPhone 14 Pro): under the tracker", function()
		local screen = v(844 - 47 - 47, 390 - 58 - 21)
		local cases = {
			{ "tutorial", phoneCorner(screen.X, CASH, widths(POUCH, DAILY)), columnOf(60, TRACKER) },
			{ "tutorial, Murph", phoneCorner(screen.X, CASH, widths(POUCH, DAILY)), columnOf(60, TRACKER + SPEECH) },
			{
				"after",
				phoneCorner(screen.X, widths(STORE, CASH), widths(CLOCK, POUCH, DAILY_STREAK)),
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
		local phone = phoneCorner(667, CASH, widths(POUCH, DAILY))
		local top = HudLayout.ToastLane(v(667, 317), phone, nil, TOAST_W, LANE_MIN)
		checkLane("phone, no column", v(667, 317), phone, nil, top)
		t.eq(top.under, false)
		-- ... and where it isn't, the lane starts under the corner at the margin.
		local wide = phoneCorner(667, CASH, widths(CLOCK, POUCH, DAILY_STREAK))
		local low = HudLayout.ToastLane(v(667, 317), wide, nil, TOAST_W, LANE_MIN)
		checkLane("phone, no column, wide corner", v(667, 317), wide, nil, low)
		t.eq({ low.left, low.top }, { 12, wide.bottom + 8 })
		-- An empty column beside a corner that leaves less than 240: under the corner.
		local empty = columnOf(60, 0)
		local under = HudLayout.ToastLane(v(667, 317), wide, empty, TOAST_W, LANE_MIN)
		checkLane("phone, empty column", v(667, 317), wide, empty, under)
		t.eq(under.top, wide.bottom + 8)
		-- ... or, with room for 240, ends left of it.
		local mid = phoneCorner(667, CASH, widths(POUCH, DAILY, 60))
		local beside = HudLayout.ToastLane(v(667, 317), mid, empty, TOAST_W, LANE_MIN)
		checkLane("phone, empty column, mid corner", v(667, 317), mid, empty, beside)
		t.eq(beside.top, 68)
		t.eq(beside.right, mid.left - 8)
	end)

	-- A shop open over the game (UI-03). The panel as ShopUI places it (in
	-- its screen's offsets, which ignore the top bar), moved into the HUD
	-- screen's offsets (under the top bar), where the HUD works out the lane.
	local PAPER, HEADER = 8, 14 + 30 + 2 + 16 + 10 -- ShopUI: the wood frame, the title and subtitle block
	local function shopPanel(w, h, inset)
		local area = HudLayout.ClearOf(areaOn(w, h), PANEL, cashRow(w, inset, 12), 8, 400)
		local p = HudLayout.Centred(area, PANEL)
		return { left = p.left, top = p.top - inset, right = p.right, bottom = p.bottom - inset }
	end
	-- The strip down the panel's right side with the rows' buttons: the
	-- button (ShopUI's, from UITheme.Sizes: 96 wide on a phone, 100 on a
	-- computer) inside the row's 12 padding, the list's 12 + 8 (the scroll
	-- bar) and the frame.
	local function buttonsOf(panel, phone)
		local right = panel.right - PAPER - 20 - 12
		return {
			left = right - (if phone then PHONE else DESK).ShopBuy.size.X,
			top = panel.top + PAPER + HEADER,
			right = right,
			bottom = panel.bottom,
		}
	end
	-- `hotbar`: the top of Roblox's tool hotbar band, on a phone.
	local function checkModal(name, panel, lane, phone, hotbar)
		t.eq(lane.modal, true, name)
		if hotbar then
			t.ok(lane.bottom <= hotbar, name .. ": above the tool hotbar")
		else
			t.eq(lane.bottom, panel.bottom - 8, name .. ": 8 above the panel's bottom edge")
		end
		t.ok(lane.left >= panel.left and lane.right <= panel.right, name .. ": inside the panel")
		t.ok(lane.top >= panel.top + PAPER + HEADER, name .. ": below the title and subtitle")
		t.ok(clear(lane, buttonsOf(panel, phone), 8), name .. ": clear of the Buy buttons")
		t.ok(lane.right - lane.left >= LANE_MIN, name .. ": wide enough for a toast")
		t.ok(lane.bottom - lane.top >= lane.max * 34, name .. ": room for its toasts (34 each at least)")
	end

	-- Roblox's tool hotbar on a phone: the bottom 70 of the HUD screen
	-- (UITheme.Bottom(): the 12 margin and 58), drawn over everything.
	local PHONE_HOTBAR = 12 + 58

	t.test("a shop open on a 667 x 375 phone: one toast, inside the panel, above the tool hotbar", function()
		for _, inset in ipairs({ 36, 58 }) do
			local screen = v(667, 375 - inset)
			local panel = shopPanel(667, 375, inset)
			t.ok(panel.right - panel.left >= 400, "the panel as ShopUI fits it, left of the cash row")
			-- The evidence: the lane under the tracker sits on the panel.
			local corner = phoneCorner(667, CASH, widths(POUCH, DAILY))
			local under = HudLayout.ToastLane(screen, corner, columnOf(60, TRACKER), TOAST_W, LANE_MIN, screen.Y - 12)
			t.ok(not clear(under, panel, 0), "today's lane is over the panel")
			-- And the panel reaches down over the hotbar: a toast at its
			-- bottom edge would be half under it.
			local hotbar = screen.Y - PHONE_HOTBAR
			t.ok(panel.bottom - 8 > hotbar, "the panel's bottom edge is in the hotbar's band")
			local lane = HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, true, hotbar)
			checkModal("SE " .. inset, panel, lane, true, hotbar)
			t.eq(lane.max, 1, "one toast on a phone")
			t.eq(lane.left, panel.left + PAPER + 12, "lined up with the rows")
			t.eq(lane.bottom, hotbar, "just above the hotbar")
		end
	end)

	t.test("over the hotbar: the lane never climbs above one toast under the panel's middle", function()
		local panel = { left = 100, top = 40, right = 500, bottom = 340 } -- middle 190
		local high = HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, true, 150)
		t.eq(high.bottom, 190 + 48, "one toast's room under the middle")
		t.ok(high.top >= 190, "in the panel's lower half")
		-- A hotbar below the panel changes nothing.
		local low = HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, true, 400)
		t.eq(low, HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, true))
		t.eq(low.bottom, 332)
	end)

	t.test("a shop open in a 1366 x 768 window: up to three, growing up from its bottom edge", function()
		for _, inset in ipairs({ 36, 58 }) do
			local screen = v(1366, 768 - inset)
			local panel = shopPanel(1366, 768, inset)
			t.eq(panel.right - panel.left, 560, "the full-size panel")
			-- The evidence: the lane at the top covers the panel's title.
			local corner = cornerOf(1366, widths(STORE, CLOCK, CASH), widths(POUCH, DAILY))
			local top = HudLayout.ToastLane(screen, corner, columnOf(250, TRACKER), TOAST_W, LANE_MIN, screen.Y - 12)
			local title = {
				left = panel.left + PAPER,
				top = panel.top + PAPER,
				right = panel.right - PAPER,
				bottom = panel.top + PAPER + HEADER,
			}
			local reach = { left = top.left, top = top.top, right = top.right, bottom = top.top + top.max * 48 }
			t.ok(not clear(reach, title, 0), "three toasts at the top reach the title")
			local lane = HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, false)
			checkModal("1366 " .. inset, panel, lane, false)
			t.eq(lane.max, 3)
			t.ok(lane.top >= (panel.top + panel.bottom) / 2, "in the panel's lower half")
			t.eq(lane.right - lane.left, TOAST_W, "a full-width toast")
		end
	end)

	t.test("a panel too narrow to keep clear of its buttons: the narrowest lane, still inside it", function()
		local panel = { left = 100, top = 40, right = 400, bottom = 340 } -- 300 wide
		local lane = HudLayout.ModalLane(panel, TOAST_W, LANE_MIN, true)
		t.eq({ lane.left, lane.right }, { 120, 360 })
		t.eq(lane.bottom, 332)
		local tiny = HudLayout.ModalLane({ left = 0, top = 0, right = 100, bottom = 80 }, TOAST_W, LANE_MIN, false)
		t.ok(tiny.right >= tiny.left and tiny.right <= 100, "never wider than the panel")
		t.eq(tiny.max, 1, "a short panel takes one")
	end)

	-- The bottom line (UI-04): the load chip, then the hint, on the hint's
	-- line above the hotbar (UITheme.Bottom(): 70 up on a phone).
	local HINT_CAP, ROW_GAP, PHONE_BOTTOM = 320, 8, 70
	local HintLogic = t.shared("HintLogic")
	t.eq(PHONE.Hint.text, 14, "the phone's hint is 14 px")
	-- GothamMedium 14 (a phone's hint) runs under 7.6 px a character; the
	-- pill's padding is 14 + 14.
	local function hintWidth(line)
		return #line * 7.6 + 28
	end
	-- "Hands 1/2", up to "Hands 2/2 · Bed 12/12" in GothamBold 14 (under 8 px
	-- a character), with the log, the gaps and the padding.
	local CHIPS = { 150, 216 }
	-- Roblox's touch jump button on a small screen: 70 px, 95 in from the
	-- right and 90 up from the bottom (full-screen pixels), here in the HUD
	-- screen's offsets (under the top bar).
	local function jumpOn(w, h, inset)
		return { left = w - 95, top = h - 90 - inset, right = w - 25, bottom = h - 20 - inset }
	end
	-- The chip's and the hint's boxes as the row lays them out.
	local function rowOn(screen, chipW, hintW, high)
		local hintMax, centre = HudLayout.BottomRow(screen.X, chipW, hintW, ROW_GAP, 12, high, HINT_CAP)
		local shown = math.min(hintW, hintMax)
		local width = (if chipW > 0 then chipW + ROW_GAP else 0) + shown
		local left = centre - width / 2
		local bottom = screen.Y - PHONE_BOTTOM
		local chip = if chipW > 0
			then { left = left, top = bottom - 30, right = left + chipW, bottom = bottom }
			else nil
		local hintLeft = if chipW > 0 then left + chipW + ROW_GAP else left
		return chip, { left = hintLeft, top = bottom - 30, right = hintLeft + shown, bottom = bottom }, hintMax
	end

	t.test("667 x 375: the load chip and the hint share a line, apart, clear of the jump button, uncut", function()
		for _, inset in ipairs({ 36, 58 }) do
			local screen = v(667, 375 - inset)
			local jump = jumpOn(667, 375, inset)
			for _, context in ipairs(HintLogic.Contexts) do
				local line = HintLogic.Pick("phone", context)
				for _, chipW in ipairs(CHIPS) do
					local name = string.format("SE %d, %q, chip %d", inset, line, chipW)
					local chip, hint, hintMax = rowOn(screen, chipW, hintWidth(line), jump.left - ROW_GAP)
					t.ok(hint.bottom > jump.top, name .. ": level with the jump button")
					t.ok(clear(chip, hint, ROW_GAP - 0.01), name .. ": the chip and the hint don't overlap")
					t.ok(
						clear(chip, jump, ROW_GAP - 0.01) and clear(hint, jump, ROW_GAP - 0.01),
						name .. ": clear of jump"
					)
					t.ok(chip.left >= 12 and hint.right <= 667 - 12, name .. ": on screen")
					t.ok(hintMax >= hintWidth(line), name .. ": the hint isn't cut short")
					t.eq(hint.bottom, screen.Y - PHONE_BOTTOM, name .. ": on the hint's line, above the hotbar")
				end
			end
		end
	end)

	t.test("568 x 320: the row moves left, then the hint truncates, before it reaches the jump button", function()
		local screen = v(568, 320 - 36)
		local jump = jumpOn(568, 320, 36)
		local line = HintLogic.Pick("phone", "carrying")
		local chip, hint, hintMax = rowOn(screen, 216, hintWidth(line), jump.left - ROW_GAP)
		t.ok(hintMax < hintWidth(line), "no room for all of it")
		t.ok(clear(chip, hint, ROW_GAP - 0.01))
		t.ok(clear(hint, jump, ROW_GAP - 0.01), "clear of jump")
		t.ok(chip.left >= 12 - 1e-6, "on screen")
	end)

	t.test("a computer: the row centred, the hint up to 320; with no chip the hint is where it always was", function()
		local screen = v(1366, 768 - 58)
		local hintMax, centre = HudLayout.BottomRow(1366, 180, 266, ROW_GAP, 12, 1366 - 12, HINT_CAP)
		t.eq(hintMax, HINT_CAP)
		t.eq(centre, 683)
		local chip, hint = rowOn(screen, 0, 266, 1366 - 12)
		t.eq(chip, nil)
		t.eq((hint.left + hint.right) / 2, 683, "centred, as before the chip")
	end)

	-- GothamBlack's width at `size` px, from above: capitals under 0.75 em,
	-- digits 0.68, lower case 0.62, a space 0.28, anything else 0.45.
	local function blackWidth(text, size)
		local em = 0
		for _, code in utf8.codes(text) do
			local c = utf8.char(code)
			em += if string.match(c, "^%u$")
				then 0.75
				elseif string.match(c, "^%d$") then 0.68
				elseif string.match(c, "^%l$") then 0.62
				elseif c == " " then 0.28
				else 0.45
		end
		return em * size
	end

	t.test("640 x 360 after the tutorial: the corner's second line stays clear of the Field Guide button", function()
		local HudRules = t.load("StarterPlayer/StarterPlayerScripts/HudRules")
		local daily, clock, pouch = PHONE.DailyButton, PHONE.Clock, PHONE.Pouch
		-- The clock's longest text fits its pill.
		t.ok(blackWidth("Night 23:45", clock.text) <= clock.size.X, "the clock fits")
		-- Line 2: [clock][pouch][Daily Goals], right-aligned at the margin, 7
		-- under the cash row; the Field Guide button tops the left column at
		-- y 60 (UITheme's phone column), in the same screen's offsets.
		local function line2(label)
			local dailyW = math.max(daily.size.X, blackWidth(label, daily.text) + 20) -- its padding: 10 + 10
			local w = widths(clock.size.X, pouch.size.X, dailyW)
			return { left = 640 - 12 - w, top = 8 + 49 + 7, right = 640 - 12, bottom = 8 + 49 + 7 + daily.size.Y }
		end
		local guide = { left = 12, top = 60, right = 12 + PHONE.FieldGuide.size.X, bottom = 60 + GUIDE }
		for _, streak in ipairs({ 0, 1, 9, 10, 99, 100, 999 }) do
			local label = HudRules.DailyLabel(1, 3, streak, true)
			t.ok(clear(line2(label), guide, 8), string.format("%q: clear of the Field Guide", label))
		end
		-- The evidence: the computer's label, at a phone's 14 px, comes within
		-- 8 px of the button from a 10-day streak.
		t.ok(not clear(line2(HudRules.DailyLabel(1, 3, 10, false)), guide, 8), "the long label reaches it")
		-- Line 1 (the Store and the cash row) ends above the column.
		t.ok(8 + 49 <= guide.top, "line 1 is above the Field Guide")
	end)

	t.test("the clock: beside the cash on a computer, line 2 on a phone, hidden there in the tutorial", function()
		t.eq(HudLayout.ClockLine(false, 0), "beside")
		t.eq(HudLayout.ClockLine(false, 3), "beside")
		t.eq(HudLayout.ClockLine(true, 0), "under")
		t.eq(HudLayout.ClockLine(true, 1), "none")
		t.eq(HudLayout.ClockLine(true, 7), "none")
	end)
end
