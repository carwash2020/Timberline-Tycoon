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
		}) do
			local ok, why = run(w, request)
			t.eq(ok, false, request.op)
			t.eq(why, "filled", request.op)
		end
		t.eq(w.cash, 500)
		t.eq(#w.placed, 1)
		t.eq(w.placed[1].x, 0)

		-- Copy is not an edit of the source. A full wall still copies.
		local built = ghost("Wall", 0, 0, "src")
		built.fill = { units = 8 }
		built.wood = "birch"
		built.data = { x = 1, y = 2 }
		w = world({ built }, 500)
		local copied, copyWhy = run(w, { op = "copy", uids = { "src" }, dx = 16, dz = 0 })
		t.eq(copied, true, copyWhy)
		t.eq(#w.placed, 2)
		t.eq(w.cash, 468, "the ghost costs the full $32")
		t.eq(w.placed[1].wood, "birch")
		t.eq(w.placed[1].fill.units, 8)
		t.eq(w.placed[1].data, { x = 1, y = 2 })
		t.eq(w.placed[1].x, 0)
		local made = w.placed[2]
		t.eq(made.wood, nil)
		t.eq(made.fill.units, 0)
		t.eq(made.data, nil)
		t.eq(made.paid, 32)
		t.eq(made.x, 16)

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
		local PlotPickerLogic = t.shared("PlotPickerLogic")
		local function clear(w, h)
			t.eq(BuilderBar.Fits(w, h), true, w .. "x" .. h)
			local layout = BuilderBar.Layout(w, h)
			t.ok(layout.button >= 44, string.format("%dx%d button %.1f", w, h, layout.button))
			t.ok(layout.rows == 1 or layout.rows == 2, "one or two rows")
			local bar = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
			for _, block in ipairs(PlotPickerLogic.TouchBlockers(w, h)) do
				t.eq(PlotPickerLogic.BoxesOverlap(bar, block), false, w .. "x" .. h)
			end
			return layout
		end
		local phone = clear(667, 375)
		t.eq(phone.rows, 2, "the landscape gap is 248px, so two rows of four")
		t.eq(phone.button, 56)
		t.eq(phone.w, 248)
		local tall = clear(375, 667)
		t.eq(tall.rows, 2)
		t.ok(tall.button >= 44)
		local desk = clear(1920, 1080)
		t.eq(desk.rows, 1)
		t.eq(desk.button, 56)
		t.eq(#BuilderBar.Names, 8)
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

	t.test("667 x 375 and 375 x 667: the bar clears the hotbar and the touch controls", function()
		local PlotPickerLogic = t.shared("PlotPickerLogic")
		-- UITheme.Bottom() on a phone is 70. Build mode hides BottomRow, so
		-- the bar does not reserve a hint row above the hotbar.
		t.eq(BuilderBar.PhoneBottom, 70)
		t.eq(BuilderBar.Air, 8)
		for _, size in ipairs({ { 667, 375 }, { 375, 667 } }) do
			local w, h = size[1], size[2]
			local layout = BuilderBar.Layout(w, h)
			local bar = { x = layout.x, y = layout.y, w = layout.w, h = layout.h }
			local hotbar = { x = 0, y = h - BuilderBar.PhoneBottom, w = w, h = BuilderBar.PhoneBottom }
			t.eq(PlotPickerLogic.BoxesOverlap(bar, hotbar), false, w .. "x" .. h .. " hotbar")
			for _, block in ipairs(PlotPickerLogic.TouchBlockers(w, h)) do
				t.eq(PlotPickerLogic.BoxesOverlap(bar, block), false, w .. "x" .. h .. " controls")
			end
			t.ok(layout.button >= 44, string.format("%dx%d button %.1f", w, h, layout.button))
		end
		local phone = BuilderBar.Layout(667, 375)
		t.eq(phone.h, 156, "two rows, readout included")
		t.eq(phone.y, 141, "375 - 70 - 156 - 8")
		local tall = BuilderBar.Layout(375, 667, 70)
		t.ok(tall.button >= 44)
	end)

	t.test("a move off the plot or above the build height is refused", function()
		local w = world({ ghost("Wall") })
		t.eq(select(2, run(w, { op = "move", uid = "Wall", x = 80, z = 0, rot = 0 })), "bounds")
		t.eq(w.placed[1].x, 0)
		local tooHigh = PlotData.MaxBuildY + PlotData.HeightStep
		t.eq(select(2, run(w, { op = "move", uid = "Wall", x = 0, z = 0, rot = 0, y = tooHigh })), "grid")
		t.eq(w.placed[1].y, nil)
		t.eq(w.cash, 1000)
	end)

	t.test("deleting an unfilled 16-stud wall refunds exactly $64", function()
		local w = world({ ghost("Wall") }, 200)
		t.eq(run(w, { op = "resize", uid = "Wall", len = 16 }), true)
		t.eq(w.placed[1].paid, 64)
		local cash = w.cash
		t.eq(run(w, { op = "delete", uid = "Wall" }), true)
		t.eq(w.cash - cash, 64)
		t.eq(#w.placed, 0)
	end)

	t.test("wood drops that undo, and a later undo does not pay it back", function()
		local item = ghost("Wall")
		local w = world({ item }, 500)
		t.eq(run(w, { op = "resize", uid = "Wall", len = 16 }), true)
		t.eq(w.cash, 468)
		item.wood = "birch"
		local ok, why = EditLogic.Undo(w)
		t.eq(ok, false)
		t.eq(why, "gone")
		t.eq(#w.undo, 0, "the entry is dropped")
		t.eq(w.cash, 468)
		t.eq(w.placed[1].len, 16)
		ok, why = EditLogic.Undo(w)
		t.eq(ok, false)
		t.eq(why, "empty")
		t.eq(w.cash, 468)
	end)

	t.test("rot survives a save and load", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{
				uid = "turned",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 2,
				fill = { units = 0 },
				paid = 32,
			},
		}
		Schema.Migrate(data)
		t.eq(data.plot.placed[1].rot, 2)
		local again = Util.deepCopy(data)
		Schema.Migrate(again)
		t.eq(again.plot.placed[1].rot, 2, "a second load keeps the turn")
	end)

	-- PlotService owns the wallet cap and the memory-only undo stack.
	local function plotServer(options)
		options = options or {}
		local Vector2, Vector3 = t.roblox.Vector2, t.roblox.Vector3
		local Instance = {}
		local methods = {}
		function methods:SetAttribute(key, value)
			self._attrs[key] = value
		end
		function methods:GetAttribute(key)
			return self._attrs[key]
		end
		function methods:GetChildren()
			return table.clone(self._children)
		end
		function methods:FindFirstChild(name)
			for _, child in ipairs(self._children) do
				if child.Name == name then
					return child
				end
			end
			return nil
		end
		function methods:ClearAllChildren()
			for _, child in ipairs(self:GetChildren()) do
				child.Parent = nil
			end
		end
		function methods:Destroy()
			self.Parent = nil
		end
		function methods:IsA(class)
			return class == self.ClassName or (class == "BasePart" and self.ClassName == "Part")
		end
		function methods:PivotTo(cframe)
			self.pivot = cframe
		end
		function Instance.new(className)
			local props = { ClassName = className, Name = className, _children = {}, _attrs = {} }
			local inst = {}
			return setmetatable(inst, {
				__index = function(_, key)
					if props[key] ~= nil then
						return props[key]
					end
					if key == "Triggered" or key == "OnServerEvent" then
						local signal = {}
						function signal:Connect(fn)
							self.fn = fn
						end
						props[key] = signal
						return signal
					end
					return methods[key]
				end,
				__newindex = function(_, key, value)
					if key == "Parent" then
						local old = props.Parent
						if old then
							local list = old._children
							table.remove(list, table.find(list, inst))
						end
						if value then
							table.insert(value._children, inst)
						end
					end
					props[key] = value
				end,
			})
		end

		local toasts = {}
		local base = t.loader()
		local serverSchema = base:server("ProfileSchema")
		local serverUtil = base:shared("Util")
		local serverPlot = base:shared("PlotData")
		local profiles = {}
		local function newPlayer(userId, name)
			local profile = serverUtil.deepCopy(serverSchema.Template)
			profile.cash = options.cash or 1000
			local root = { Position = Vector3.new(0, 3, 0) }
			local player = {
				UserId = userId,
				Name = name,
				DisplayName = name,
				attrs = {},
				Character = {
					FindFirstChild = function(_, child)
						return if child == "HumanoidRootPart" then root else nil
					end,
				},
				SetAttribute = function(self, key, value)
					self.attrs[key] = value
				end,
			}
			profiles[player] = profile
			function player.standOn(i)
				local c = if i then serverPlot.Slots[i] else Vector2.new(-2000, -2000)
				root.Position = Vector3.new(c.X, 3, c.Y)
			end
			player.root = root
			return player, profile
		end
		local loader = t.loader({
			globals = {
				Instance = Instance,
				task = {
					spawn = function(fn)
						fn()
					end,
				},
			},
			services = {
				CollectionService = {
					AddTag = function() end,
				},
			},
			mocks = {
				ProfileService = {
					GetProfile = function(player)
						return profiles[player]
					end,
				},
				RateLimiter = {
					Allow = function()
						return true
					end,
				},
				QuestService = {
					Event = function() end,
				},
				EconomyService = {
					SpendCash = function(player, amount)
						local profile = profiles[player]
						if profile.cash < amount then
							return false
						end
						profile.cash -= amount
						return true
					end,
					Refund = function(player, amount)
						profiles[player].cash += amount
						return amount, 0
					end,
				},
				BlueprintModels = {
					Build = function(bp)
						local model = Instance.new("Model")
						model.Name = bp.id
						return model
					end,
					Place = function(model, _plotCFrame, x, z, rot)
						model.placedAt = { x, z, rot }
					end,
				},
				MachineArt = {
					Build = function(id)
						local model = Instance.new("Model")
						model.Name = id
						return model
					end,
					SetCut = function() end,
				},
			},
		})
		local PlotService = loader:server("PlotService")
		local map = Instance.new("Folder")
		local remotes = {}
		for _, name in ipairs({ "PlaceBlueprint", "MoveBlueprint", "SellPlaced", "UpgradePlot" }) do
			remotes[name] = Instance.new("RemoteEvent")
		end
		PlotService.Init(map, remotes, function(_, message)
			table.insert(toasts, message)
		end)
		local plots = map:FindFirstChild("Plots")
		local function claim(player, i)
			local board = plots:FindFirstChild("Plot_" .. i):FindFirstChild("Sign")
			player.root.Position = board.CFrame.Position
			board:FindFirstChild("ProximityPrompt").Triggered.fn(player)
		end
		return {
			P = PlotService,
			newPlayer = newPlayer,
			claim = claim,
			toasts = toasts,
			lastToast = function()
				return toasts[#toasts]
			end,
		}
	end

	t.test("undoing a copy that would overflow the wallet changes nothing", function()
		local GameConfig = t.shared("GameConfig")
		local s = plotServer({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = {
			{
				uid = "wall",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				paid = 32,
			},
		}
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Edit(ann, { op = "copy", uids = { "wall" }, dx = 16, dz = 0 })
		t.eq(#profile.plot.placed, 2)
		t.eq(profile.cash, 968)
		local copyUid = profile.plot.placed[2].uid
		profile.cash = GameConfig.CashCap
		s.P.Edit(ann, { op = "undo" })
		t.eq(#profile.plot.placed, 2)
		t.eq(profile.plot.placed[2].uid, copyUid)
		t.eq(profile.cash, GameConfig.CashCap)
		t.eq(s.lastToast(), "Your wallet is too full for that. Spend some first.")
		profile.cash = 0
		s.P.Edit(ann, { op = "undo" })
		t.eq(#profile.plot.placed, 1)
		t.eq(profile.plot.placed[1].uid, "wall")
		t.eq(profile.cash, 32, "the copy's fee comes back once the wallet has room")
	end)

	t.test("the undo stack is empty after a leave and rejoin", function()
		local s = plotServer({ cash = 1000 })
		local ann, profile = s.newPlayer(1, "Ann")
		profile.plot.placed = {
			{
				uid = "wall",
				blueprintId = "Wall",
				x = 0,
				z = 0,
				rot = 0,
				fill = { units = 0 },
				paid = 32,
			},
		}
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Edit(ann, { op = "rotate", uid = "wall", rot = 1 })
		t.eq(profile.plot.placed[1].rot, 1)
		s.P.PlayerRemoving(ann)
		s.claim(ann, 1)
		ann.standOn(1)
		s.P.Edit(ann, { op = "undo" })
		t.eq(profile.plot.placed[1].rot, 1, "the turn stays")
		t.eq(s.lastToast(), "Nothing to undo.")
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
		-- B02 moved the full plot from 39.4 h to 32.0 h (the square price).
		-- The other four headlines stay.
		t.ok(string.find(report, "32.0 h", 1, true) ~= nil)
	end)
end
