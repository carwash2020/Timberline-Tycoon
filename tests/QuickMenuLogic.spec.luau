--!nocheck
-- QuickMenuLogic: the View button's one job, the tiles' order and layout,
-- and that adding it breaks no bind rule (InputKit, HudRules).
return function(t)
	local Enum = t.roblox.Enum
	local fs = require("@lune/fs")
	local Menu = t.shared("QuickMenuLogic")
	local InputKit = t.shared("InputKit")

	t.test("the View button opens it; it is no D-pad, X, Y, L3 or world key", function()
		t.eq(Menu.OpenGamepad, Enum.KeyCode.ButtonSelect)
		for _, banned in ipairs({
			Enum.KeyCode.ButtonL3,
			Enum.KeyCode.ButtonX,
			Enum.KeyCode.ButtonY,
			Enum.KeyCode.ButtonA,
			Enum.KeyCode.ButtonB,
			Enum.KeyCode.DPadUp,
			Enum.KeyCode.DPadDown,
			Enum.KeyCode.DPadLeft,
			Enum.KeyCode.DPadRight,
		}) do
			t.ok(Menu.OpenGamepad ~= banned, banned.Name)
		end
	end)

	t.test("InputKit lists it once, in the menu context, and every context stays unique", function()
		local found = 0
		for _, bind in ipairs(InputKit.Target.menu) do
			if bind.gamepad == Menu.OpenGamepad then
				found += 1
				t.eq(bind.action, "QuickMenu")
			end
		end
		t.eq(found, 1)
		for _, context in ipairs({ "placer", "drag", "menu" }) do
			t.ok(InputKit.KeysUnique(InputKit.Target[context], false), context)
		end
		t.ok(InputKit.KeysUnique(InputKit.Target.world, true))
		-- No other context uses the View button.
		for _, context in ipairs({ "world", "placer", "drag" }) do
			for _, bind in ipairs(InputKit.Target[context]) do
				t.ok(bind.gamepad ~= Menu.OpenGamepad, context .. " " .. bind.action)
			end
		end
		-- And it is safe while the placer is up with world prompts on.
		t.ok(InputKit.PlacerSafe({ { action = "QuickMenu", gamepad = Menu.OpenGamepad } }, true))
	end)

	t.test("no other client file binds the View button", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		local users = {}
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") then
				local source = fs.readFile(dir .. entry)
				if string.find(source, "KeyCode.ButtonSelect", 1, true) then
					table.insert(users, entry)
				end
			end
		end
		t.eq(users, {}, "they all go through QuickMenuLogic.OpenGamepad")
		local ui = fs.readFile(dir .. "QuickMenuUI.luau")
		t.ok(string.find(ui, "QuickMenuLogic.OpenGamepad", 1, true))
		t.ok(string.find(ui, "BindActionAtPriority", 1, true), "an action over the panels' own")
	end)

	t.test("tiles come in the canonical order, unknown ones after by label, repeats once", function()
		local sorted = Menu.Sort({
			{ id = "owner", label = "OWNER" },
			{ id = "zzz", label = "ZED" },
			{ id = "store", label = "STORE" },
			{ id = "aaa", label = "AARDVARK" },
			{ id = "saves", label = "SAVES" },
			{ id = "store", label = "STORE AGAIN" },
			{ id = "badges", label = "BADGES" },
		})
		local ids = {}
		for _, e in ipairs(sorted) do
			table.insert(ids, e.id)
		end
		t.eq(ids, { "saves", "store", "badges", "owner", "aaa", "zzz" })
		t.eq(sorted[2].label, "STORE", "the first of a repeated id wins")
	end)

	t.test("every destination the brief names has a place in the order", function()
		local have = {}
		for _, id in ipairs(Menu.Order) do
			t.ok(not have[id], id .. " listed twice")
			have[id] = true
		end
		for _, id in ipairs({
			"saves",
			"store",
			"badges",
			"daily",
			"guide",
			"settings",
			"land",
			"owner",
			"tutorial",
			"hud",
		}) do
			t.ok(have[id], id)
		end
		t.eq(Menu.IdFor("Saves"), "saves")
		t.eq(Menu.IdFor("DropAxe"), "dropaxe")
		t.eq(Menu.IdFor("Call Truck!"), "calltruck")
	end)

	t.test("labels are capitalised and capped to fit a tile", function()
		t.eq(Menu.Label("Saves"), "SAVES")
		t.eq(#Menu.Label("A very long button label that overflows"), Menu.MaxLabel - 1 + #"…")
		t.eq(Menu.Label("Send truck home"), "SEND TRUCK HOME")
	end)

	t.test("the layout is a grid of equal tiles with explicit, wrapping links", function()
		local layout = Menu.Layout(8, 900, 500)
		t.eq(layout.columns, 3)
		t.eq(layout.rows, 3)
		t.eq(#layout.rects, 8)
		t.eq(layout.cellW, Menu.TileW)
		t.ok(layout.cellH >= Menu.MinTileH)
		t.ok(layout.cellW >= Menu.TileW * 0.75)
		-- Equal steps along a row and a column.
		local r = layout.rects
		t.eq(r[2].x - r[1].x, layout.cellW + layout.gap)
		t.eq(r[4].y - r[1].y, layout.cellH + layout.gap)
		-- Nothing outside the grid, nothing overlapping.
		for i = 1, #r do
			t.ok(r[i].x >= 0 and r[i].x + r[i].w <= layout.gridW + 1e-9, "tile " .. i .. " is inside across")
			t.ok(r[i].y >= 0 and r[i].y + r[i].h <= layout.gridH + 1e-9, "tile " .. i .. " is inside down")
			for j = i + 1, #r do
				local apart = r[i].x + r[i].w <= r[j].x
					or r[j].x + r[j].w <= r[i].x
					or r[i].y + r[i].h <= r[j].y
					or r[j].y + r[j].h <= r[i].y
				t.ok(apart, i .. " and " .. j .. " overlap")
			end
		end
		t.eq(layout.links[1].left, 3, "left from the first tile wraps to the row's last")
		t.eq(layout.links[1].up, 7, "up from the top wraps to the bottom of that column")
		t.eq(layout.links[8].right, 7)
	end)

	t.test("a narrow screen uses fewer columns instead of clipping tiles", function()
		local layout = Menu.Layout(8, 400, 800)
		t.ok(layout.columns < 3, "columns: " .. layout.columns)
		t.ok(layout.gridW <= 400 + 1e-9)
		local tiny = Menu.Layout(12, 300, 200)
		t.ok(tiny.cellH >= 1)
		t.ok(tiny.gridW <= 300 + 1e-9 or tiny.columns == 1)
		t.eq(Menu.Layout(0, 800, 600).rows, 0)
		t.eq(#Menu.Layout(1, 800, 600).rects, 1)
	end)

	t.test("B, Escape and the open button close it; A and the stick do not", function()
		t.eq(Menu.Closes(Enum.KeyCode.ButtonB), true)
		t.eq(Menu.Closes(Enum.KeyCode.Escape), true)
		t.eq(Menu.Closes(Enum.KeyCode.ButtonSelect), true)
		t.eq(Menu.Closes(Enum.KeyCode.ButtonA), false)
		t.eq(Menu.Closes(Enum.KeyCode.Thumbstick1), false)
	end)

	t.test("it will not open while you type", function()
		t.eq(Menu.CanOpen(false), true)
		t.eq(Menu.CanOpen(true), false)
	end)

	t.test("HudRules still holds: the new files bind no D-pad key and no extra shortcut", function()
		local dir = "src/StarterPlayer/StarterPlayerScripts/"
		for _, file in ipairs({ "GamepadNav.luau", "HudNav.luau", "QuickMenuUI.luau", "MenuPad.luau" }) do
			local source = fs.readFile(dir .. file)
			t.eq(string.find(source, "KeyCode.DPad", 1, true), nil, file .. " names no D-pad key")
			t.eq(string.find(source, "HUD.PadShortcut", 1, true), nil, file .. " adds no pad shortcut")
		end
		for _, file in ipairs({ "GamepadNavLogic.luau", "QuickMenuLogic.luau" }) do
			local source = fs.readFile("src/ReplicatedStorage/Shared/" .. file)
			t.eq(string.find(source, "KeyCode.DPad", 1, true), nil, file .. " names no D-pad key")
		end
	end)
end
