--!nocheck
-- GamepadNavLogic: reading order, nearest-neighbour links with wrap, the
-- quick menu's grid, and what closing a panel does with the selection.
return function(t)
	local Logic = t.shared("GamepadNavLogic")

	local function node(id, x, y, w, h)
		return { id = id, x = x, y = y, w = w or 100, h = h or 40 }
	end

	local function ids(list)
		local out = {}
		for _, n in ipairs(list) do
			table.insert(out, n.id)
		end
		return out
	end

	-- The HUD as it sits on a TV: the corner pills across the top, the left
	-- column down the left, the side buttons down the right.
	local function hud()
		return {
			node("store", 400, 10, 90, 36),
			node("clock", 500, 12, 100, 32), -- a few px lower: still the same row
			node("daily", 610, 10, 200, 36),
			node("guide", 20, 120, 130, 40),
			node("badges", 20, 170, 130, 40),
			node("saves", 1100, 300, 160, 48),
			node("hammer", 1100, 360, 160, 48),
			node("menu", 1100, 240, 160, 48),
		}
	end

	t.test("reading order: rows top to bottom, left to right inside a row", function()
		local order = Logic.Order(hud())
		-- Row one is the top strip, then the left column (y 120, 170) mixed with
		-- nothing else; the side column sits lower down at x 1100.
		t.eq(ids(order), { "store", "clock", "daily", "guide", "badges", "menu", "saves", "hammer" })
		t.eq(Logic.First(hud()).id, "store", "selection starts on the first logical button")
		t.eq(Logic.First({}), nil)
	end)

	t.test("reading order is stable: input order and ties never change it", function()
		local a = hud()
		local b = {}
		for i = #a, 1, -1 do
			table.insert(b, a[i])
		end
		t.eq(ids(Logic.Order(a)), ids(Logic.Order(b)))
		local same = { node("b", 10, 10), node("a", 10, 10) }
		t.eq(ids(Logic.Order(same)), { "a", "b" }, "same spot: by id")
		-- NaN and infinity positions are treated as 0 rather than breaking the sort.
		local odd = { node("x", 0 / 0, 0), node("y", math.huge, 0), node("z", 5, 0) }
		t.eq(#Logic.Order(odd), 3)
	end)

	t.test("links go to the nearest button that way", function()
		local links = Logic.Links(hud(), true)
		t.eq(links.store.right, "clock")
		t.eq(links.clock.right, "daily")
		t.eq(links.clock.left, "store")
		t.eq(links.guide.down, "badges")
		t.eq(links.badges.up, "guide")
		t.eq(links.saves.up, "menu")
		t.eq(links.saves.down, "hammer")
		t.eq(links.menu.down, "saves")
		t.eq(links.daily.right, "menu", "off the end of the top strip toward the side column")
		t.eq(links.store.down, "guide", "down from the corner reaches the left column")
		t.eq(links.guide.up, "store")
	end)

	t.test("links wrap: a push with nothing that way goes round to the far side", function()
		local links = Logic.Links(hud(), true)
		t.eq(links.badges.down, "guide", "down off the bottom of a column: its own top")
		t.eq(links.hammer.down, "menu", "likewise the side column")
		t.eq(links.menu.right, "badges", "right off the screen's edge: round to the left column")
		t.eq(links.guide.left, "menu", "and back")
		t.eq(links.daily.up, "hammer", "up off the top: the bottom of the nearest column")
		-- Every push goes somewhere else in a layout of many buttons.
		for id, link in pairs(links) do
			for _, dir in ipairs(Logic.Directions) do
				t.ok(link[dir] ~= nil, id .. " has a " .. dir .. " link")
				t.ok(link[dir] ~= id, id .. " " .. dir .. " does not point at itself with others around")
			end
		end
	end)

	t.test("every button can be reached from the first by pushes", function()
		local nodes = hud()
		local links = Logic.Links(nodes, true)
		local seen = { [Logic.First(nodes).id] = true }
		local queue = { Logic.First(nodes).id }
		local head = 1
		while head <= #queue do
			local link = links[queue[head]]
			head += 1
			for _, dir in ipairs(Logic.Directions) do
				local target = link[dir]
				if target and not seen[target] then
					seen[target] = true
					table.insert(queue, target)
				end
			end
		end
		for _, n in ipairs(nodes) do
			t.ok(seen[n.id], n.id .. " is reachable")
		end
	end)

	t.test("a push never hops far across the screen to something only a little lower", function()
		local nodes = { node("a", 0, 0, 100, 40), node("b", 0, 60, 100, 40), node("far", 2000, 70, 100, 40) }
		local links = Logic.Links(nodes, true)
		t.eq(links.b.down, "a", "down off the bottom wraps to the column's top, not to the far one")
		t.eq(links.a.down, "b")
	end)

	t.test("without wrap an edge button has no link past the edge", function()
		local links = Logic.Links(hud(), false)
		t.eq(links.badges.down, nil)
		t.eq(links.menu.right, nil)
		t.eq(links.store.right, "clock")
	end)

	t.test("one button stays put; two wrap onto each other", function()
		local one = Logic.Links({ node("a", 0, 0) }, true)
		t.eq(one.a, { up = "a", down = "a", left = "a", right = "a" })
		local two = Logic.Links({ node("a", 0, 0), node("b", 200, 0) }, true)
		t.eq(two.a.right, "b")
		t.eq(two.b.right, "a")
		t.eq(two.a.left, "b")
		t.eq(two.a.up, "b", "a single row: up and down go to the only other button")
	end)

	t.test("a staggered grid links by the line, not the corner", function()
		local grid = {}
		for row = 0, 2 do
			for col = 0, 2 do
				table.insert(grid, node(row .. col, col * 120, row * 60, 100, 48))
			end
		end
		local links = Logic.Links(grid, true)
		t.eq(links["00"].right, "01")
		t.eq(links["11"].up, "01")
		t.eq(links["11"].down, "21")
		t.eq(links["11"].left, "10")
		t.eq(links["02"].right, "00", "wraps within its row")
		t.eq(links["20"].down, "00", "and within its column")
	end)

	t.test("grid links step one tile and wrap in rows and columns", function()
		local links = Logic.GridLinks(7, 3) -- 3 / 3 / 1
		t.eq(links[1], { up = 7, down = 4, left = 3, right = 2 })
		t.eq(links[3], { up = 7, down = 6, left = 2, right = 1 })
		t.eq(links[5], { up = 2, down = 8 > 7 and 7 or 8, left = 4, right = 6 })
		t.eq(links[7], { up = 4, down = 1, left = 7, right = 7 }, "a lone last tile: left and right stay on it")
		-- Every link is a real tile.
		for i = 1, 7 do
			for _, dir in ipairs(Logic.Directions) do
				local target = links[i][dir]
				t.ok(target >= 1 and target <= 7, i .. " " .. dir)
			end
		end
		t.eq(Logic.GridLinks(0, 3), {})
		t.eq(Logic.GridLinks(1, 3)[1], { up = 1, down = 1, left = 1, right = 1 })
	end)

	t.test("a full grid walks a full circle in every direction", function()
		for _, count in ipairs({ 2, 3, 4, 6, 9, 12 }) do
			local columns = Logic.Columns(count)
			local links = Logic.GridLinks(count, columns)
			local at = 1
			for _ = 1, count do
				at = links[at].right
			end
			-- Around a row (or a short last row) comes back to where it began.
			local row = math.floor((1 - 1) / columns)
			t.eq(math.floor((at - 1) / columns), row, count .. " tiles: right stays on the row")
		end
	end)

	t.test("columns: up to 3 in a row, then 3 across to 9, then 4", function()
		t.eq(Logic.Columns(0), 1)
		t.eq(Logic.Columns(1), 1)
		t.eq(Logic.Columns(3), 3)
		t.eq(Logic.Columns(4), 3)
		t.eq(Logic.Columns(9), 3)
		t.eq(Logic.Columns(10), 4)
		t.eq(Logic.Columns(16), 4)
	end)

	t.test("grid rects are evenly spaced and a short last row is centred", function()
		local cw, ch, gap = 100, 50, 10
		local a = Logic.GridRect(1, 5, 3, cw, ch, gap)
		local b = Logic.GridRect(2, 5, 3, cw, ch, gap)
		local c = Logic.GridRect(3, 5, 3, cw, ch, gap)
		t.eq({ a.x, a.y }, { 0, 0 })
		t.eq(b.x - a.x, cw + gap)
		t.eq(c.x - b.x, cw + gap)
		local d = Logic.GridRect(4, 5, 3, cw, ch, gap)
		local e = Logic.GridRect(5, 5, 3, cw, ch, gap)
		t.eq(d.y, ch + gap)
		t.eq(e.x - d.x, cw + gap)
		local w = Logic.GridSize(5, 3, cw, ch, gap)
		t.eq(w, 3 * cw + 2 * gap)
		-- Two tiles in the last row sit centred under the three above.
		t.eq(d.x + (e.x + cw - d.x) / 2, w / 2)
		local _, h = Logic.GridSize(5, 3, cw, ch, gap)
		t.eq(h, 2 * ch + gap)
		t.eq({ Logic.GridSize(0, 3, cw, ch, gap) }, { 0, 0 })
	end)

	t.test("a grid that would not fit shrinks its tiles, never below the minimum height", function()
		local w, h = Logic.FitCell(12, 4, 400, 300, 168, 64, 12, 48)
		t.ok(w <= (400 - 3 * 12) / 4 + 1e-9)
		t.ok(h <= (300 - 2 * 12) / 3 + 1e-9)
		t.ok(h >= 48 or h == (300 - 2 * 12) / 3)
		local fw, fh = Logic.FitCell(6, 3, 2000, 2000, 168, 64, 12, 48)
		t.eq({ fw, fh }, { 168, 64 }, "room to spare: the wanted size")
		local _, tiny = Logic.FitCell(12, 4, 2000, 100, 168, 64, 12, 48)
		t.eq(tiny, 48, "never under the minimum height")
	end)

	t.test("closing a panel: back to the opener, let go, or leave a selection that moved on", function()
		local ready = { shown = true, selectable = true }
		t.eq(Logic.Restore(ready, true, false), "opener", "inside the panel: back to the HUD button")
		t.eq(Logic.Restore(ready, false, true), "opener", "nothing selected: back to the HUD button")
		t.eq(Logic.Restore(ready, false, false), "keep", "the selection is somewhere else now")
		t.eq(Logic.Restore(nil, true, false), "clear", "opened with no button: walking again")
		t.eq(Logic.Restore(nil, false, true), "keep", "nothing to do")
		t.eq(Logic.Restore({ shown = false, selectable = true }, true, false), "clear", "the opener went away")
		t.eq(Logic.Restore({ shown = true, selectable = false }, true, false), "clear")
	end)

	t.test("the opener is the named button, else the one selected outside the panel", function()
		t.eq(Logic.Opener("hud", "other", false), "hud", "the quick menu names it")
		t.eq(Logic.Opener(nil, "store", false), "store")
		t.eq(Logic.Opener(nil, "inside", true), nil, "a selection already in the panel is not an opener")
		t.eq(Logic.Opener(nil, nil, false), nil)
	end)

	t.test("B and Escape close everywhere; the quick menu's own button closes it", function()
		t.eq(Logic.Closes("ButtonB"), true)
		t.eq(Logic.Closes("Escape"), true)
		t.eq(Logic.Closes("ButtonA"), false)
		t.eq(Logic.Closes("ButtonSelect"), false)
		t.eq(Logic.Closes("ButtonSelect", "ButtonSelect"), true)
	end)

	t.test("HUD buttons are big enough for a stick on a gamepad", function()
		t.eq({ Logic.PadSize(110, 40) }, { Logic.PadButtonW, Logic.PadButtonH })
		t.eq({ Logic.PadSize(300, 80) }, { 300, 80 }, "never smaller than they were")
	end)
end
