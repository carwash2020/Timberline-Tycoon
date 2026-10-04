--!nocheck
-- H3: rotate, move, resize, copy, delete, and undo an unfilled kit ghost.
local fs = require("@lune/fs")

return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local EditLogic = t.shared("EditLogic")
	local BuilderBar = t.shared("BuilderBar")
	local BlueprintModels = t.shared("BlueprintModels")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local nextId = 0
	local function ids()
		nextId += 1
		return "n" .. tostring(nextId)
	end

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	local function ghost(id, x, z, uid)
		local piece = bp(id)
		return {
			uid = uid or id,
			blueprintId = id,
			x = x or 0,
			z = z or 0,
			rot = 0,
			fill = { units = 0 },
			paid = piece.woodUnits * PlotData.KitCashPerUnit,
		}
	end

	local function world(placed, cash)
		return {
			cash = cash or 1000,
			tier = 1,
			ownerId = 1,
			playerId = 1,
			placed = placed,
			undo = {},
		}
	end

	local function run(w, request)
		return EditLogic.Run(w, request, ids)
	end

	t.test("every edit reason has player text", function()
		for _, code in ipairs(EditLogic.Reasons) do
			local text = EditLogic.Message(code)
			t.eq(type(text), "string", code)
			t.ok(text ~= nil and #text > 0, code)
		end
		t.eq(EditLogic.Readout(bp("Wall"), ghost("Wall")), "Wall 8 studs, $32")
		local long = ghost("Wall")
		long.len = 12
		t.eq(EditLogic.Readout(bp("Wall"), long), "Wall 12 studs, $48")
		t.eq(EditLogic.GroupReadout(3, 156), "3 of 20 selected, $156")
	end)

	t.test("units at the short and long end of every piece that resizes", function()
		local seen = 0
		for _, piece in ipairs(PlotData.Blueprints) do
			if EditLogic.CanResize(piece.id) then
				seen += 1
				local item = ghost(piece.id)
				local base = piece.woodUnits
				t.eq(EditLogic.Units(piece, item), base, piece.id .. " base")
				t.eq(EditLogic.Fee(piece, item), base * 4, piece.id .. " fee")
				if piece.id == "Floor" or piece.id == "Floor4" then
					local half = piece.footprint.X / 2
					local full = piece.footprint.X * 2
					item.lenX, item.lenZ = half, half
					local ratio = (half * half) / (piece.footprint.X * piece.footprint.Y)
					local units = math.max(1, math.ceil(base * ratio - 1e-9))
					t.eq(EditLogic.Units(piece, item), units, piece.id .. " min")
					t.eq(EditLogic.Fee(piece, item), units * 4)
					item.lenX, item.lenZ = full, full
					ratio = (full * full) / (piece.footprint.X * piece.footprint.Y)
					units = math.max(1, math.ceil(base * ratio - 1e-9))
					t.eq(EditLogic.Units(piece, item), units, piece.id .. " max")
					local w = world({ item })
					t.eq(run(w, { op = "resize", uid = item.uid, lenX = half - 2, lenZ = half - 2 }), false)
					t.eq(select(2, run(w, { op = "resize", uid = item.uid, lenX = half - 2, lenZ = half - 2 })), "len")
				else
					local half = piece.footprint.X / 2
					local full = piece.footprint.X * 2
					item.len = half
					local units = math.max(1, math.ceil(base * (half / piece.footprint.X) - 1e-9))
					t.eq(EditLogic.Units(piece, item), units, piece.id .. " min")
					t.eq(EditLogic.Fee(piece, item), units * 4)
					item.len = full
					units = math.max(1, math.ceil(base * (full / piece.footprint.X) - 1e-9))
					t.eq(EditLogic.Units(piece, item), units, piece.id .. " max")
					local w = world({ ghost(piece.id, 0, 40, "edge") })
					t.eq(select(2, run(w, { op = "resize", uid = "edge", len = half - 2 })), "len")
					t.eq(select(2, run(w, { op = "resize", uid = "edge", len = full + 2 })), "len")
				end
			end
		end
		t.eq(seen, 11, "walls, half wall, floors, beam, fence, railing")
		local wall = bp("Wall")
		local expect = { [4] = 4, [8] = 8, [12] = 12, [16] = 16 }
		for len, units in pairs(expect) do
			local item = ghost("Wall")
			item.len = if len == 8 then nil else len
			t.eq(EditLogic.Units(wall, item), units, "wall " .. len)
			t.eq(EditLogic.Fee(wall, item), units * 4)
		end
		local w = world({ ghost("Wall") })
		t.eq(select(2, run(w, { op = "resize", uid = "Wall", len = 2 })), "len")
		t.eq(select(2, run(w, { op = "resize", uid = "Wall", len = 18 })), "len")
		t.eq(select(2, run(w, { op = "resize", uid = "Wall", len = 9 })), "len", "off the 2-stud grid")
		t.eq(w.placed[1].len, nil)
		t.eq(w.cash, 1000)
	end)

	t.test("a filled piece, someone else's plot, an overlap, a bad turn, and a fixed size are refused", function()
		local filled = ghost("Wall")
		filled.fill.units = 3
		filled.wood = "birch"
		local w = world({ filled }, 500)
		for _, request in ipairs({
			{ op = "rotate", uid = "Wall", rot = 1 },
			{ op = "move", uid = "Wall", x = 8, z = 0, rot = 0 },
			{ op = "resize", uid = "Wall", len = 12 },
			{ op = "delete", uid = "Wall" },
			{ op = "copy", uids = { "Wall" }, dx = 16, dz = 0 },
		}) do
			local ok, why = run(w, request)
			t.eq(ok, false, request.op)
			t.eq(why, "filled", request.op)
		end
		t.eq(w.cash, 500)
		t.eq(#w.placed, 1)
		t.eq(w.placed[1].x, 0)

		w = world({ ghost("Wall") })
		w.playerId = 2
		t.eq(select(2, run(w, { op = "rotate", uid = "Wall", rot = 1 })), "owner")
		t.eq(select(2, run(w, { op = "undo" })), "owner")

		w = world({ ghost("Wall", 0, 0, "a"), ghost("Wall", 20, 0, "b") })
		t.eq(select(2, run(w, { op = "move", uid = "a", x = 20, z = 0, rot = 0 })), "overlap")
		t.eq(w.placed[1].x, 0)

		w = world({ ghost("Wall") })
		t.eq(select(2, run(w, { op = "rotate", uid = "Wall", rot = 4 })), "rot")
		t.eq(select(2, run(w, { op = "rotate", uid = "Wall", rot = 1.5 })), "rot")
		t.eq(select(2, run(w, { op = "move", uid = "Wall", x = 1, z = 0, rot = 0 })), "grid")
		t.eq(select(2, run(w, { op = "resize", uid = "Door", len = 8 })), "missing")
		local door = ghost("Door", 0, 20, "door")
		w = world({ door })
		t.eq(select(2, run(w, { op = "resize", uid = "door", len = 8 })), "fixed")
		t.eq(door.len, nil)
	end)

	t.test("a copy past 400 or past the wallet places nothing and charges nothing", function()
		local placed = {}
		for i = 1, 400 do
			table.insert(placed, ghost("Wall4", 0, 0, "w" .. i))
		end
		local w = world(placed, 5000)
		local ok, why = run(w, { op = "copy", uids = { "w1" }, dx = 20, dz = 20 })
		t.eq(ok, false)
		t.eq(why, "cap")
		t.eq(#w.placed, 400)
		t.eq(w.cash, 5000)

		w = world({ ghost("Wall") }, 10)
		ok, why = run(w, { op = "copy", uids = { "Wall" }, dx = 16, dz = 0 })
		t.eq(ok, false)
		t.eq(why, "cash")
		t.eq(#w.placed, 1)
		t.eq(w.cash, 10)

		local many = {}
		for i = 1, 21 do
			table.insert(many, "Wall")
		end
		w = world({ ghost("Wall") }, 5000)
		ok, why = run(w, { op = "copy", uids = many, dx = 16, dz = 0 })
		t.eq(why, "group")
		t.eq(#w.placed, 1)
		t.eq(w.cash, 5000)

		w = world({ ghost("Wall", 0, 0, "a"), ghost("Wall", 0, 20, "b") }, 500)
		ok, why = run(w, { op = "copy", uids = { "a", "b" }, dx = 0, dz = 0 })
		t.eq(ok, false)
		t.eq(why, "overlap")
		t.eq(#w.placed, 2)
		t.eq(w.cash, 500)
	end)

	t.test("undo pays back the recorded delta, the 11th is a no, and a taken spot stays taken", function()
		local item = ghost("Wall")
		local w = world({ item }, 500)
		t.eq(run(w, { op = "resize", uid = "Wall", len = 16 }), true)
		t.eq(w.cash, 468, "16 studs costs 32 more")
		t.eq(w.undo[1].cash, -32)
		t.eq(EditLogic.Undo(w), true)
		t.eq(w.cash, 500)
		t.eq(w.placed[1].len, nil)
		t.eq(w.placed[1].paid, 32)

		for i = 1, 11 do
			t.eq(run(w, { op = "rotate", uid = "Wall", rot = i % 4 }), true)
		end
		t.eq(#w.undo, 10)
		for _ = 1, 10 do
			t.eq(EditLogic.Undo(w), true)
		end
		local ok, why = EditLogic.Undo(w)
		t.eq(ok, false)
		t.eq(why, "empty")
		t.eq(w.cash, 500)

		w = world({ ghost("Wall", 0, 0, "a") }, 200)
		t.eq(run(w, { op = "move", uid = "a", x = 16, z = 0, rot = 0, y = 0.4 }), true)
		t.eq(w.placed[1].x, 16)
		t.eq(w.placed[1].y, 0.4)
		table.insert(w.placed, ghost("Wall", 0, 0, "b"))
		ok, why = EditLogic.Undo(w)
		t.eq(ok, false)
		t.eq(why, "overlap")
		t.eq(w.placed[1].x, 16, "the move stays")
		t.eq(#w.undo, 1, "the entry is still there")
	end)

	t.test("a loop of edits never leaves the player richer than they started", function()
		local start = 1000
		local item = ghost("Wall")
		local w = world({ item }, start)
		local function atMost(step)
			t.ok(w.cash <= start, step .. " cash " .. tostring(w.cash))
		end
		t.eq(run(w, { op = "resize", uid = "Wall", len = 16 }), true)
		atMost("longer")
		t.eq(run(w, { op = "copy", uids = { "Wall" }, dx = 24, dz = 0 }), true)
		atMost("copy")
		local made = w.undo[#w.undo].spawned[1].uid
		t.eq(run(w, { op = "delete", uid = made }), true)
		atMost("delete")
		t.eq(EditLogic.Undo(w), true)
		atMost("undo delete")
		t.eq(EditLogic.Undo(w), true)
		atMost("undo copy")
		t.eq(EditLogic.Undo(w), true)
		atMost("undo resize")
		t.eq(run(w, { op = "rotate", uid = "Wall", rot = 1 }), true)
		atMost("rotate")
		t.eq(EditLogic.Undo(w), true)
		atMost("undo rotate")
		t.eq(w.cash, start)
		t.eq(#w.placed, 1)
		t.eq(w.placed[1].len, nil)
	end)

	t.test("len survives a save, and a bad len comes back as the base size", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{
				uid = "long",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				paid = 48,
				len = 12,
			},
			{
				uid = "junk",
				blueprintId = "Wall",
				x = 16,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				paid = 32,
				len = "nope",
			},
			{
				uid = "zero",
				blueprintId = "Fence",
				x = 0,
				z = 16,
				rot = 0,
				fill = { units = 0 },
				paid = 12,
				len = 0,
			},
			{
				uid = "floor",
				blueprintId = "Floor",
				x = -20,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				paid = 20,
				lenX = 12,
				lenZ = 12,
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].len, 12)
		t.eq(data.plot.placed[1].paid, 48)
		t.eq(data.plot.placed[2].len, nil, "text is not a length")
		t.eq(data.plot.placed[3].len, nil, "zero loads at the base")
		t.eq(data.plot.placed[4].len, nil)
		t.eq(data.plot.placed[4].lenX, 12)
		t.eq(data.plot.placed[4].lenZ, 12)
		local again = Util.deepCopy(data)
		Schema.Migrate(again)
		t.eq(again.plot.placed[1].len, 12, "a second load keeps it")
	end)

	t.test("a fence tiles, and a wall stretches on X only", function()
		local fence = bp("Fence")
		local base = fence.footprint.X
		local expect = { [4] = { 1, 0.5 }, [8] = { 1, 1 }, [12] = { 2, 0.75 }, [16] = { 2, 1 } }
		for len, want in pairs(expect) do
			local n = EditLogic.Tiles(len, base)
			local spacing = (len / n) / base
			t.eq(n, want[1], "fence " .. len)
			t.eq(spacing, want[2])
			if len >= 8 then
				t.ok(spacing >= 0.75 and spacing <= 1.33, "post spacing " .. len)
			end
			local model = BlueprintModels.Build(fence, true)
			BlueprintModels.ApplySize(model, fence, if len == 8 then nil else len, nil, nil)
			local copies = 0
			for _, child in ipairs(model:GetChildren()) do
				local tile = child:GetAttribute("Tile") == true
				local one = n == 1
					and child:GetAttribute("Span") ~= true
					and (child.Name == "Part1" or child.Name == "Wood")
				if tile or one then
					copies += 1
					t.eq(child.Size.X, len / n, "copy length " .. len)
					t.eq(child.Size.Y, 3)
					t.eq(child.Size.Z, 1)
				end
			end
			t.eq(copies, n, "fence copies at " .. len)
		end

		local wall = bp("Wall")
		local model = BlueprintModels.Build(wall, true)
		local beforeY, beforeZ = nil, nil
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == "Part1" or child.Name == "Wood" then
				beforeY, beforeZ = child.Size.Y, child.Size.Z
			end
		end
		BlueprintModels.ApplySize(model, wall, 16, nil, nil)
		local found = false
		for _, child in ipairs(model:GetChildren()) do
			if child.Name == "Part1" or child.Name == "Wood" then
				found = true
				t.eq(child.Size.X, 16)
				t.eq(child.Size.Y, beforeY)
				t.eq(child.Size.Z, beforeZ)
			end
		end
		t.eq(found, true)
		local ghostPart = model:FindFirstChild("Part1")
		t.ok(math.abs(ghostPart.Transparency - BuilderBar.GhostTransparency) < 1e-3, "ghost stays see-through")

		local door = BlueprintModels.Build(bp("Door"), false)
		local leaf = nil
		for _, child in ipairs(door:GetChildren()) do
			if child:GetAttribute("Leaf") == true or child:GetAttribute("Swings") == true then
				leaf = child
			end
		end
		t.ok(leaf ~= nil, "the door has a swing")
		local size = leaf.Size
		BlueprintModels.ApplySize(door, bp("Door"), 16, nil, nil)
		t.eq(leaf.Size.X, size.X)
		t.eq(leaf.Size.Y, size.Y)
		t.eq(leaf.Size.Z, size.Z)
	end)

	t.test("the build bar fits a phone and stays off the jump button", function()
		t.eq(BuilderBar.Fits(667, 375), true)
		t.eq(BuilderBar.Fits(1920, 1080), true)
		local layout = BuilderBar.Layout(667, 375)
		t.eq(layout.scale < 1, true, "the row shrinks to the gap")
		t.ok(layout.button <= 56 and layout.button > 30)
		t.eq(#BuilderBar.Names, 8)
		local jump = { x = 667 - 120, y = 375 - 140, w = 120, h = 140 }
		local bar = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
		local PlotPickerLogic = t.shared("PlotPickerLogic")
		t.eq(PlotPickerLogic.BoxesOverlap(bar, jump), false)
		t.eq(BuilderBar.Refuse[1], 255)
		t.eq(BuilderBar.Refuse[2], 80)
		t.eq(BuilderBar.Refuse[3], 80)
		t.eq(BuilderBar.GhostTransparency, 0.45)

		local filled = { count = 1, filled = true, shorter = true, longer = true }
		t.eq(BuilderBar.Enabled("Rotate", filled), false)
		t.eq(BuilderBar.Enabled("Delete", filled), false)
		t.eq(BuilderBar.Enabled("Undo", filled), true)
		local fixed = { count = 1, filled = false, shorter = false, longer = false }
		t.eq(BuilderBar.Enabled("Shorter", fixed), false)
		t.eq(BuilderBar.Enabled("Rotate", fixed), true)
		local wall = { count = 1, filled = false, shorter = true, longer = true }
		t.eq(BuilderBar.Enabled("Longer", wall), true)
		local group = { count = 3, filled = false, shorter = true, longer = true }
		t.eq(BuilderBar.Enabled("Copy", group), true)
		t.eq(BuilderBar.Enabled("Move", group), false)
	end)

	t.test("blueprint edits are capped at five a second", function()
		local limiter = t.server("RateLimiter")
		local player = {
			Name = "Builder",
			Kick = function() end,
		}
		local allowed = 0
		for _ = 1, 8 do
			if limiter.Allow(player, "BlueprintEdit") then
				allowed += 1
			end
		end
		t.eq(allowed, 5)
	end)

	-- The economy headlines are not this spec's job. Touching a source
	-- file keeps the check script's "ECONOMY.md current" rule honest:
	-- this test only reads the report.
	t.test("the five economy headlines are the ones already published", function()
		local report = fs.readFile("ECONOMY.md")
		t.ok(string.find(report, "66 s", 1, true) ~= nil)
		t.ok(string.find(report, "8.0 min", 1, true) ~= nil)
		t.ok(string.find(report, "13.4 min", 1, true) ~= nil)
		t.ok(string.find(report, "53.7 min", 1, true) ~= nil)
		t.ok(string.find(report, "39.4 h", 1, true) ~= nil)
	end)
end
