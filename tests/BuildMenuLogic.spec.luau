--!nocheck
-- BuildMenuLogic: the categories cover every entry exactly once, a card reads the
-- way BlueprintBook.Row says, the D-pad has no dead end, the category rail wraps.
return function(t)
	local BuildMenuLogic = t.shared("BuildMenuLogic")
	local BlueprintBook = t.shared("BlueprintBook")
	local PlotData = t.shared("PlotData")
	local fs = require("@lune/fs")

	local function allIds()
		local ids = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			table.insert(ids, bp.id)
		end
		return ids
	end

	local PlotLogic = t.shared("PlotLogic")
	local MACHINE = "SawmillRickety" -- a boxed machine: placed from stock, no kind

	local function boxed()
		return MACHINE
	end

	-- A fresh book, a full book, a stocked machine.
	local function cases()
		local machine = boxed()
		local fresh = BlueprintBook.Entries(BlueprintBook.Starter(), {}, true)
		local full = BlueprintBook.Entries(allIds(), {}, true)
		local stocked = BlueprintBook.Entries(BlueprintBook.Starter(), { [machine] = 2 }, true)
		return { fresh = fresh, full = full, stocked = stocked }
	end

	t.test("the categories cover every entry exactly once (fresh, full and stocked books)", function()
		for name, entries in pairs(cases()) do
			t.ok(#entries > 0, name .. " has entries")
			local seen, total = {}, 0
			for _, cat in ipairs(BuildMenuLogic.Categories(entries)) do
				t.ok(#cat.entries > 0, name .. ": " .. cat.kind .. " is shown only with entries")
				for _, e in ipairs(cat.entries) do
					t.eq(seen[e.id], nil, name .. ": " .. e.id .. " is in two categories")
					seen[e.id] = cat.kind
					total += 1
				end
			end
			t.eq(total, #entries, name .. ": every entry is in one category")
			for _, e in ipairs(entries) do
				t.ok(seen[e.id] ~= nil, name .. ": " .. e.id .. " has a category")
			end
		end
	end)

	t.test("labels are 7 letters or fewer, the rail is in the brief's order, More is last", function()
		t.eq(
			BuildMenuLogic.Kinds,
			{ "Walls", "Floors", "Doors", "Stairs", "Roofs", "Fences", "Indoor", "Decor", "Houses", "More" }
		)
		for _, kind in ipairs(BuildMenuLogic.Kinds) do
			t.ok(#kind <= 7, kind .. " is " .. #kind .. " letters")
		end
		local order = {}
		for _, cat in ipairs(BuildMenuLogic.Categories(cases().full)) do
			table.insert(order, cat.kind)
		end
		t.eq(order, BuildMenuLogic.Kinds, "a full book fills every category")
	end)

	t.test("the 46 pieces with card art are in their categories; machines and glass go to More", function()
		local expect = {}
		local n = 0
		for kind, ids in pairs(PlotData.KindRows) do
			for _, id in ipairs(ids) do
				n += 1
				expect[id] = kind
				t.ok(PlotData.Blueprint(id) ~= nil, id .. " exists in the data")
				t.eq(PlotData.Blueprint(id).kind, kind, id .. " kind")
			end
		end
		t.eq(n, 46)
		local machine = boxed()
		for _, cat in ipairs(BuildMenuLogic.Categories(cases().full)) do
			for _, e in ipairs(cat.entries) do
				if expect[e.id] then
					t.eq(cat.kind, expect[e.id], e.id)
				else
					t.eq(cat.kind, "More", e.id .. " has no kind: it lands in More")
				end
			end
		end
		t.ok(PlotLogic.Blueprint(machine) ~= nil and PlotLogic.Blueprint(machine).kind == nil, "a machine has no kind")
		local more = {}
		for _, cat in ipairs(BuildMenuLogic.Categories(cases().stocked)) do
			if cat.kind == "More" then
				for _, e in ipairs(cat.entries) do
					more[e.id] = true
				end
			end
		end
		t.ok(more[machine], "a stocked machine is placeable from More")
		-- Unknown or nil kind goes to More.
		local fake = { id = "X", bp = { kind = "Nonsense" }, group = "Buildings", stock = 0 }
		t.eq(BuildMenuLogic.KindOf(fake), "More")
		fake.bp.kind = nil
		t.eq(BuildMenuLogic.KindOf(fake), "More")
	end)

	t.test("within a category the order is BlueprintBook.Entries order, locked rows last", function()
		local entries = cases().full
		local index = {}
		for i, e in ipairs(entries) do
			index[e.id] = i
		end
		for _, cat in ipairs(BuildMenuLogic.Categories(entries)) do
			local last = 0
			for _, e in ipairs(cat.entries) do
				t.ok(index[e.id] > last, cat.kind .. ": " .. e.id .. " keeps its place")
				last = index[e.id]
			end
		end
	end)

	t.test("a card's state is BlueprintBook.Row's: ready, cant or locked, never ready when locked", function()
		local ctxs = {
			{ tier = 1, cash = 0, boxed = false },
			{ tier = 1, cash = 1e9, boxed = false },
			{ tier = 5, cash = 50, boxed = false },
			{ tier = 5, cash = 1e9, boxed = false },
		}
		local sawLocked, sawCant, sawReady = false, false, false
		for _, entries in pairs(cases()) do
			for _, e in ipairs(entries) do
				for _, ctx in ipairs(ctxs) do
					local row = BlueprintBook.Row(e, ctx)
					local tile = BuildMenuLogic.Tile(e, ctx)
					t.eq(tile.id, e.id)
					t.eq(tile.name, row.name)
					t.eq(tile.sizeText, BlueprintBook.SizeText(e.bp))
					t.eq(tile.message, row.message)
					if row.state == "locked" then
						t.eq(tile.state, "locked", e.id)
						t.eq(tile.chip, row.button, e.id .. " lock chip")
						sawLocked = true
					elseif row.state == "cant" then
						t.eq(tile.state, "cant", e.id)
						t.eq(tile.chip, row.button, e.id .. " price chip")
						sawCant = true
					else
						t.eq(tile.state, "ready", e.id)
						t.eq(tile.chip, nil, e.id)
						sawReady = true
					end
					t.ok(
						not (tile.state == "ready" and not row.ready),
						e.id .. " is never ready when it cannot go ahead"
					)
					t.ok(tile.seal == "Buildings" or tile.seal == "Decor" or tile.seal == "Other")
					t.ok(tile.cost >= 0)
					if e.stock > 0 then
						t.eq(tile.cost, 0, e.id .. " is placed from stock")
						t.eq(tile.state, "ready")
					end
				end
			end
		end
		t.ok(sawLocked and sawCant and sawReady, "all three states were exercised")
	end)

	t.test("seal: Buildings, Decor and Other (machines) follow the entry's group", function()
		local seals = {}
		for _, e in ipairs(cases().stocked) do
			seals[BuildMenuLogic.Tile(e, { tier = 5, cash = 1e9, boxed = false }).seal] = true
		end
		t.ok(seals.Buildings and seals.Decor and seals.Other)
	end)

	---------------------------------------------------------------------------
	-- Navigation
	---------------------------------------------------------------------------

	t.test("Step: no dead end: every tile is reachable from tile 1, every move stays inside the grid", function()
		for count = 1, 30 do
			for cols = 3, 4 do
				local reached = { [1] = true }
				local frontier = { 1 }
				while #frontier > 0 do
					local i = table.remove(frontier)
					for _, dir in ipairs({ "up", "down", "left", "right" }) do
						local j = BuildMenuLogic.Step(count, cols, i, dir)
						t.ok(
							j >= 1 and j <= count,
							string.format("count %d cols %d: %s from %d gives %d", count, cols, dir, i, j)
						)
						if not reached[j] then
							reached[j] = true
							table.insert(frontier, j)
						end
					end
				end
				for i = 1, count do
					t.ok(reached[i], string.format("count %d cols %d: tile %d is reachable", count, cols, i))
				end
			end
		end
	end)

	t.test("Step: clamps at the edges, handles a short last row", function()
		-- 7 tiles, 3 columns:  1 2 3 / 4 5 6 / 7
		t.eq(BuildMenuLogic.Step(7, 3, 1, "left"), 1, "left edge")
		t.eq(BuildMenuLogic.Step(7, 3, 3, "right"), 3, "right edge")
		t.eq(BuildMenuLogic.Step(7, 3, 2, "up"), 2, "top edge")
		t.eq(BuildMenuLogic.Step(7, 3, 7, "right"), 7, "the short row ends at 7")
		t.eq(BuildMenuLogic.Step(7, 3, 7, "down"), 7, "bottom edge")
		t.eq(BuildMenuLogic.Step(7, 3, 5, "down"), 7, "down from a column the last row lacks: the last tile")
		t.eq(BuildMenuLogic.Step(7, 3, 4, "down"), 7)
		t.eq(BuildMenuLogic.Step(7, 3, 6, "down"), 7)
		t.eq(BuildMenuLogic.Step(7, 3, 2, "down"), 5)
		t.eq(BuildMenuLogic.Step(7, 3, 5, "up"), 2)
		t.eq(BuildMenuLogic.Step(7, 3, 5, "left"), 4)
		t.eq(BuildMenuLogic.Step(7, 3, 5, "right"), 6)
		t.eq(BuildMenuLogic.Step(1, 3, 1, "down"), 1, "one tile")
		t.eq(BuildMenuLogic.Step(0, 3, 1, "down"), 0, "no tiles")
	end)

	t.test("NextCategory wraps both ways; FirstTile is 1", function()
		t.eq(BuildMenuLogic.NextCategory(1, 4, 1), 2)
		t.eq(BuildMenuLogic.NextCategory(4, 4, 1), 1, "wraps forward")
		t.eq(BuildMenuLogic.NextCategory(1, 4, -1), 4, "wraps back")
		t.eq(BuildMenuLogic.NextCategory(3, 4, -1), 2)
		t.eq(BuildMenuLogic.NextCategory(1, 1, 1), 1)
		t.eq(BuildMenuLogic.FirstTile({ kind = "Walls", label = "Walls", entries = {} }), 1)
	end)

	t.test("columns: a phone has 3; a computer or a TV fits clamp(floor(width / 178), 3, 4)", function()
		t.eq(BuildMenuLogic.Columns(900, true), 3)
		t.eq(BuildMenuLogic.Columns(400, false), 3)
		t.eq(BuildMenuLogic.Columns(534, false), 3)
		t.eq(BuildMenuLogic.Columns(712, false), 4)
		t.eq(BuildMenuLogic.Columns(2000, false), 4)
	end)

	t.test("sizes are the brief's", function()
		local p, w = BuildMenuLogic.PhoneSizes, BuildMenuLogic.WideSizes
		t.eq(
			{ p.rail, p.row, p.icon, p.bar, p.label, p.tileW, p.tileH, p.plate, p.name, p.minText, p.stroke },
			{ 132, 56, 44, 6, 16, 150, 120, 42, 16, 14, 4 }
		)
		t.eq(
			{ w.rail, w.row, w.icon, w.bar, w.label, w.tileW, w.tileH, w.plate, w.name, w.minText, w.stroke },
			{ 200, 60, 48, 6, 18, 170, 140, 48, 18, 14, 4 }
		)
	end)

	t.test("the removed test card appears nowhere, and the long window is renamed", function()
		local needle = "Corrugated " .. "Wall Stub"
		local function scan(dir)
			for _, name in ipairs(fs.readDir(dir)) do
				local path = dir .. "/" .. name
				if fs.isDir(path) then
					if name ~= ".git" and name ~= "Vendor" then
						scan(path)
					end
				elseif
					string.match(name, "%.luau$")
					or string.match(name, "%.md$")
					or string.match(name, "%.json$")
				then
					t.eq(string.find(fs.readFile(path), needle, 1, true), nil, path)
				end
			end
		end
		scan("src")
		scan("tests")
		t.eq(PlotData.Blueprint("TallPictureWall12").displayName, "Tall Long Window")
	end)
end
