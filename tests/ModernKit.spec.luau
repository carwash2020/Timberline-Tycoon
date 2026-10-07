--!nocheck
-- The modern kit: paint, glass, overhang roofs, stairs, balcony, the glass
-- plan in the General Store, and the three sample builds.
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local PieceSize = t.shared("PieceSize")
	local ModernKit = t.shared("ModernKit")
	local KitPaint = t.shared("KitPaint")
	local BlueprintBook = t.shared("BlueprintBook")
	local BlueprintModels = t.shared("BlueprintModels")
	local HammerLogic = t.shared("HammerLogic")
	local EditLogic = t.shared("EditLogic")
	local SampleBuilds = t.shared("SampleBuilds")
	local StoreStock = t.shared("StoreStock")
	local AdminLogic = t.shared("AdminLogic")
	local Schema = t.server("ProfileSchema")
	local Util = t.shared("Util")

	local function bp(id)
		return PlotData.Blueprint(id)
	end

	local function partsOf(model)
		local out = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Root" then
				table.insert(out, d)
			end
		end
		return out
	end

	local function onGrid(value)
		local steps = value / PlotData.HeightStep
		return math.abs(steps - math.floor(steps + 0.5)) < 1e-3
	end

	---------------------------------------------------------------------
	-- Paint
	---------------------------------------------------------------------

	t.test("paint: twelve colours, natural first, every one a real hex, ids unique", function()
		t.eq(#KitPaint.Palette, 12)
		t.eq(KitPaint.Palette[1].id, "natural")
		local seen = {}
		for _, swatch in ipairs(KitPaint.Palette) do
			t.ok(not seen[swatch.id], "duplicate " .. swatch.id)
			seen[swatch.id] = true
			if swatch.id ~= "natural" then
				t.ok(string.match(swatch.color, "^#%x%x%x%x%x%x$") ~= nil, swatch.id .. " colour")
			end
			t.ok(swatch.name ~= "", swatch.id .. " name")
		end
		for _, id in ipairs({
			"white",
			"offwhite",
			"charcoal",
			"black",
			"darkbrown",
			"redbrown",
			"tan",
			"slate",
			"sage",
			"brick",
			"mustard",
		}) do
			t.ok(seen[id], id .. " is on the palette")
		end
		t.eq(KitPaint.Get("natural").name, "Wood (natural)")
	end)

	t.test("paint: only a palette id is valid; a save keeps a real colour and drops the rest", function()
		t.eq(KitPaint.Valid("charcoal"), true)
		t.eq(KitPaint.Valid("natural"), true)
		for _, bad in ipairs({ "pink", "", 5, true, false }) do
			t.eq(KitPaint.Valid(bad), false, tostring(bad))
		end
		t.eq(KitPaint.Valid(nil), false)
		t.eq(KitPaint.Clean("charcoal"), "charcoal")
		t.eq(KitPaint.Clean("natural"), nil)
		t.eq(KitPaint.Clean("pink"), nil)
		t.eq(KitPaint.Clean({}), nil)
		t.eq(KitPaint.Of({ paint = "white" }), "white")
		t.eq(KitPaint.Of({}), "natural")
		t.eq(KitPaint.Of(nil), "natural")
	end)

	t.test("paint: the server's check covers the piece, the colour, the reach and a repeat", function()
		local wall, bench = bp("Wall"), bp("Bench")
		t.eq({ KitPaint.Check(wall, nil, "white", 5) }, { true, nil })
		t.eq({ KitPaint.Check(bench, nil, "white", 5) }, { false, "piece" }, "a prebuilt piece is not painted")
		t.eq({ KitPaint.Check(nil, nil, "white", 5) }, { false, "piece" })
		t.eq({ KitPaint.Check(wall, nil, "pink", 5) }, { false, "color" })
		t.eq({ KitPaint.Check(wall, nil, 7, 5) }, { false, "color" })
		t.eq({ KitPaint.Check(wall, nil, "white", KitPaint.Reach + 1) }, { false, "far" })
		t.eq({ KitPaint.Check(wall, nil, "white", KitPaint.Reach) }, { true, nil })
		t.eq({ KitPaint.Check(wall, nil, "white", 0 / 0) }, { false, "far" })
		t.eq({ KitPaint.Check(wall, "white", "white", 5) }, { false, "same" })
		t.eq({ KitPaint.Check(wall, nil, "natural", 5) }, { false, "same" }, "already natural")
		t.eq({ KitPaint.Check(wall, "white", "natural", 5) }, { true, nil })
		for _, reason in ipairs({ "piece", "color", "far" }) do
			t.ok(KitPaint.Message(reason) ~= nil, reason .. " has player text")
		end
	end)

	t.test("paint: it never touches the fee, the planks, the size or the sell value", function()
		local wall = bp("Wall")
		local plain = { uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32 }
		local painted = { uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, paint = "charcoal" }
		t.eq(PlotLogic.SellPlan(wall, painted), PlotLogic.SellPlan(wall, plain))
		t.eq(PieceSize.Units(wall, painted), PieceSize.Units(wall, plain))
		t.eq(PieceSize.Fee(wall, painted), PieceSize.Fee(wall, plain))
		t.eq(PlotLogic.IsBuilt(wall, painted), PlotLogic.IsBuilt(wall, plain))
		t.eq(EditLogic.Locked(painted), EditLogic.Locked(plain), "paint alone does not lock a piece")
		local ghost =
			{ uid = "g", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 0 }, paint = "white" }
		t.eq(EditLogic.Locked(ghost), false, "an empty ghost can still move after it is painted")
		t.eq(EditLogic.Snapshot(ghost).paint, "white", "copies and undo keep the paint")
	end)

	t.test("paint: the hammer's sheet offers it on kit pieces only, and never locked", function()
		local ids = {}
		for _, a in
			ipairs(
				HammerLogic.PieceActions(
					bp("Wall"),
					{ uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paid = 32, fill = { units = 3 } }
				)
			)
		do
			table.insert(ids, a.id)
		end
		t.eq(ids, { "move", "turn", "paint", "sell" })
		local plain = HammerLogic.PieceActions(bp("Bench"), { uid = "a", blueprintId = "Bench", x = 0, z = 0, rot = 0 })
		t.eq(#plain, 3)
		t.eq(plain[3].id, "sell")
	end)

	t.test("paint: saved on the piece, restored on load, old saves are natural, junk is dropped", function()
		local data = Util.deepCopy(Schema.Template)
		data.plot.claimed = true
		data.plot.placed = {
			{ uid = "old", blueprintId = "Wall", x = 4, z = -2, rot = 1 },
			{ uid = "a", blueprintId = "Wall", x = 0, z = 0, rot = 0, paint = "charcoal", paid = 32 },
			{ uid = "b", blueprintId = "Wall", x = 8, z = 0, rot = 0, paint = "hot-pink" },
			{ uid = "c", blueprintId = "Wall", x = 16, z = 0, rot = 0, paint = 42 },
			{ uid = "d", blueprintId = "Bench", x = 0, z = 12, rot = 0, paint = "white" },
			{ uid = "e", blueprintId = "Wall", x = 24, z = 0, rot = 0, paint = "natural" },
			{ uid = "f", blueprintId = "ShopFront12", x = 0, z = 24, rot = 0, paint = "slate" },
		}
		Schema.Migrate(data)
		local by = {}
		for _, item in ipairs(data.plot.placed) do
			by[item.uid] = item
		end
		t.eq(by.old.paint, nil, "an old save is natural")
		t.eq(by.a.paint, "charcoal")
		t.eq(by.a.paid, 32, "the fee paid is untouched")
		t.eq(by.b.paint, nil)
		t.eq(by.c.paint, nil)
		t.eq(by.d.paint, nil, "a prebuilt piece has no paint")
		t.eq(by.e.paint, nil, "natural is saved as nothing")
		t.eq(by.f.paint, "slate", "the glass pieces are kit pieces too")
		-- Idempotent.
		Schema.Migrate(data)
		t.eq(by.a.paint, "charcoal")
	end)

	t.test("paint: covers wood, door and trim parts, never glass, and wins over the wood", function()
		local wall = BlueprintModels.Build(bp("Wall"), false)
		BlueprintModels.ApplyWood(wall, "birch")
		local part = partsOf(wall)[1]
		local woodColor = part.Color
		BlueprintModels.ApplyPaint(wall, nil)
		BlueprintModels.ApplyPaint(wall, "natural")
		t.eq(part.Color, woodColor, "no paint changes nothing")
		BlueprintModels.ApplyPaint(wall, "charcoal")
		t.eq(part.Color:ToHex():lower(), "3a3d42")
		t.eq(part.Material, t.roblox.Enum.Material.SmoothPlastic)
		BlueprintModels.ApplyPaint(wall, "bogus")
		t.eq(part.Color:ToHex():lower(), "3a3d42", "an unknown id changes nothing")
		local door = BlueprintModels.Build(bp("Door"), false)
		BlueprintModels.ApplyPaint(door, "brick")
		t.eq(partsOf(door)[1].Color:ToHex():lower(), "a8412f", "the door leaf takes paint")
		local window = BlueprintModels.Build(bp("PictureWall8"), false)
		local glassBefore, frameBefore = {}, {}
		for _, p in ipairs(partsOf(window)) do
			if p:GetAttribute("Role") == "Glass" then
				table.insert(glassBefore, { p, p.Color, p.Transparency, p.Material })
			else
				table.insert(frameBefore, p)
			end
		end
		BlueprintModels.ApplyPaint(window, "white")
		for _, g in ipairs(glassBefore) do
			t.eq(g[1].Color, g[2], "glass keeps its colour")
			t.eq(g[1].Transparency, g[3])
			t.eq(g[1].Material, g[4])
		end
		for _, f in ipairs(frameBefore) do
			t.eq(f.Color:ToHex():lower(), "f4f4f0", "the frame is painted")
		end
		local roof = BlueprintModels.Build(bp("FlatRoofOver8"), false)
		BlueprintModels.ApplyPaint(roof, "white")
		local seenEdge, seenTop = false, false
		for _, p in ipairs(partsOf(roof)) do
			if p:GetAttribute("Role") == "Edge" then
				seenEdge = true
				t.eq(p.Color:ToHex():lower(), "3a3d42", "the roof's thin edge stays dark")
			else
				seenTop = true
				t.eq(p.Color:ToHex():lower(), "f4f4f0")
			end
		end
		t.ok(seenEdge and seenTop)
	end)

	---------------------------------------------------------------------
	-- The pieces
	---------------------------------------------------------------------

	t.test("pieces: ids, sizes, wood units and fees", function()
		local want = {
			PictureWall8 = { 8, 1, 5 },
			PictureWall12 = { 12, 1, 8 },
			TallPictureWall8 = { 8, 1, 8 },
			TallPictureWall12 = { 12, 1, 12 },
			GlassDoorWall8 = { 8, 1, 5 },
			ShopFront12 = { 12, 1, 9 },
			FlatRoofOver8 = { 8, 8, 14 },
			FlatRoofOver12x8 = { 12, 8, 20 },
			FlatRoofOver12 = { 12, 12, 28 },
			Fascia8 = { 8, 2, 2 },
			Awning8 = { 8, 3, 3 },
			Staircase8 = { 4, 8, 22 },
			Balcony8 = { 8, 4, 10 },
		}
		local n = 0
		for id, spec in pairs(want) do
			n += 1
			local piece = bp(id)
			t.ok(piece ~= nil, id .. " exists")
			t.eq({ piece.footprint.X, piece.footprint.Y, piece.woodUnits }, spec, id)
			t.eq(piece.kit, true, id .. " is a kit piece")
			t.eq(PlotData.Price(piece), spec[3] * PlotData.KitCashPerUnit, id .. " fee")
			t.eq(piece.tier, 1)
			t.eq(piece.footprint.X % 4, 0, id .. " length is a multiple of 4")
			t.ok(piece.priceCash > 0, id .. " legacy price")
			t.eq(PlotLogic.Check(piece, 0, 0, 0, 1, {}), true, id .. " places on an empty Campsite")
		end
		t.eq(n, #ModernKit.Pieces, "every ModernKit piece is checked here")
		-- Less wood than the solid wall of the same size.
		t.ok(bp("PictureWall8").woodUnits < bp("Wall").woodUnits)
		t.ok(bp("PictureWall12").woodUnits < bp("Wall12").woodUnits)
		t.ok(bp("TallPictureWall8").woodUnits < bp("TallWall8").woodUnits)
		t.ok(bp("TallPictureWall12").woodUnits < bp("TallWall8").woodUnits * 12 / 8 + 0.01)
		t.eq(bp("PictureWall12").boxes[1].size.Y, 6)
		t.eq(bp("TallPictureWall8").boxes[1].size.Y, 10)
	end)

	t.test("pieces: boxes stay small, in the footprint, on the 0.2 grid, with real materials", function()
		for _, piece in ipairs(ModernKit.Pieces) do
			t.ok(#piece.boxes >= 1 and #piece.boxes <= 10, piece.id .. " part budget " .. #piece.boxes)
			local model = BlueprintModels.Build(piece, false)
			t.eq(#partsOf(model), #piece.boxes, piece.id .. " one part per box")
			for i, box in ipairs(piece.boxes) do
				local where = piece.id .. " box " .. i
				t.ok(
					pcall(function()
						return t.roblox.Enum.Material[box.material]
					end),
					where .. " material"
				)
				t.ok(string.match(box.color, "^#%x%x%x%x%x%x$") ~= nil, where .. " colour")
				local bottom, top = box.offset.Y - box.size.Y / 2, box.offset.Y + box.size.Y / 2
				t.ok(bottom >= -1e-6, where .. " is under the base")
				if box.material ~= "Glass" then
					t.ok(onGrid(bottom) and onGrid(top), where .. " is off the 0.2 grid " .. bottom .. " " .. top)
				end
				local reach = (piece.overhang or 0) + 0.01
				t.ok(math.abs(box.offset.X) + box.size.X / 2 <= piece.footprint.X / 2 + reach + 1e-6, where .. " x")
				t.ok(math.abs(box.offset.Z) + box.size.Z / 2 <= piece.footprint.Y / 2 + reach + 1e-6, where .. " z")
			end
		end
	end)

	t.test("pieces: the worst plot, 400 kit pieces of the heaviest piece, stays inside the part budget", function()
		local most = 0
		for _, piece in ipairs(PlotData.Blueprints) do
			if piece.kit then
				most = math.max(most, #piece.boxes)
			end
		end
		t.ok(most <= 10, "no kit piece has more than ten boxes: " .. most)
		t.ok(PlotData.MaxKit * most <= 4000, "a full plot is at most 4,000 parts")
		t.eq(PlotData.MaxKit, 400, "the cap is kept: the modern house is about 25 pieces")
		t.eq(PlotData.MaxItems, 200)
	end)

	---------------------------------------------------------------------
	-- Glass
	---------------------------------------------------------------------

	local GLASS_IDS = {
		"PictureWall8",
		"PictureWall12",
		"TallPictureWall8",
		"TallPictureWall12",
		"GlassDoorWall8",
		"ShopFront12",
	}

	t.test("glass: translucent blue-grey Glass that still collides, in a frame it never shares a plane with", function()
		for _, id in ipairs(GLASS_IDS) do
			local piece = bp(id)
			local panes, frames = 0, 0
			for _, box in ipairs(piece.boxes) do
				if box.role == "Glass" then
					panes += 1
					t.eq(box.material, "Glass", id)
					t.eq(box.color, ModernKit.GlassColor)
					t.ok(box.size.Z <= 0.3 and box.size.Z >= 0.1, id .. " pane thickness")
					t.ok(box.size.Z <= 1 - 2 * 0.03, id .. " the pane's faces are at least 0.03 off the frame's")
				else
					frames += 1
					t.ok(box.size.Z >= 1 - 1e-6, id .. " frame depth")
					t.ok(box.role == nil, id .. " frame is wood")
				end
			end
			t.ok(panes >= 1 and frames >= 4, id .. " has panes and a frame")
			local built = BlueprintModels.Build(piece, false)
			for _, p in ipairs(partsOf(built)) do
				if p:GetAttribute("Role") == "Glass" then
					t.eq(p.Material, t.roblox.Enum.Material.Glass)
					t.ok(p.Transparency >= 0.4 and p.Transparency <= 0.5, id .. " transparency " .. p.Transparency)
					t.eq(p.CanCollide, true, id .. " glass still blocks you")
					t.eq(p.CanQuery, true, id .. " glass can be aimed at")
				end
			end
			local ghost = BlueprintModels.Build(piece, true)
			for _, p in ipairs(partsOf(ghost)) do
				if p:GetAttribute("Role") == "Glass" then
					t.ok(math.abs(p.Transparency - 0.45) < 1e-3)
					t.eq(p.CanCollide, false, id .. " a ghost does not collide")
				end
			end
			-- A wood fill tints the frame and leaves the glass.
			BlueprintModels.ApplyWood(built, "oak")
			for _, p in ipairs(partsOf(built)) do
				if p:GetAttribute("Role") == "Glass" then
					t.eq(p.Color:ToHex():lower(), "bcd3df")
				end
			end
		end
	end)

	t.test("glass: a door hangs in the glass door wall and the shop front, and nowhere else new", function()
		local door = bp("Door")
		for _, host in ipairs({ "DoorWall8", "GlassDoorWall8", "ShopFront12" }) do
			t.eq(PlotLogic.DoorHosts[host], true, host)
			local y = 0.4
			local placed = { { uid = "h", blueprintId = host, x = 0, z = 0, rot = 0, y = y } }
			t.eq(PlotLogic.Check(door, 0, 0, 0, 1, placed, nil, y), true, host .. " takes a door")
			t.eq(PlotLogic.Check(door, 2, 0, 0, 1, placed, nil, y), false, host .. " door off the doorway")
		end
		t.eq(
			PlotLogic.Check(door, 0, 0, 0, 1, { { uid = "h", blueprintId = "PictureWall8", x = 0, z = 0, rot = 0 } }),
			false
		)
		t.eq(PlotLogic.Check(door, 0, 0, 0, 1, {}), false, "a door needs a doorway")
		-- The doorway really is clear of the frame.
		for _, id in ipairs({ "GlassDoorWall8", "ShopFront12" }) do
			local slot = bp(id).slot
			t.eq(slot.size, t.roblox.Vector3.new(4, 6, 1))
			for _, box in ipairs(bp(id).boxes) do
				local inside = math.abs(box.offset.X) + box.size.X / 2 <= 2 + 1e-6
				t.eq(inside, false, id .. " nothing stands in the doorway")
			end
		end
	end)

	t.test("glass: a corner of glass walls and a house wall meet like walls do", function()
		local placed = { { uid = "a", blueprintId = "PictureWall12", x = 0, z = 0, rot = 0, y = 0.4 } }
		t.eq(PlotLogic.Check(bp("PictureWall12"), 6, 6, 1, 1, placed, nil, 0.4), true, "an L corner")
		t.eq(PlotLogic.Check(bp("Wall"), 0, 0, 0, 1, placed, nil, 0.4), false, "a wall cannot share the line")
		t.eq(PlotLogic.Check(bp("PictureWall12"), 12, 0, 0, 1, placed, nil, 0.4), true, "end to end")
	end)

	---------------------------------------------------------------------
	-- The General Store plan
	---------------------------------------------------------------------

	t.test("store: one plan, $500, teaches all six glass pieces; the rest are not starter plans", function()
		local key = bp("PictureWall8")
		t.eq(key.unlock, true)
		t.eq(PlotData.StorePrice(key), 500)
		t.eq(PlotData.Price(key), 20, "placing still costs the kit fee")
		t.eq(#key.family, 6)
		t.eq(#key.family, #GLASS_IDS)
		for _, id in ipairs(GLASS_IDS) do
			t.ok(table.find(key.family, id), id .. " is in the family")
			t.eq(BlueprintBook.IsStarter(bp(id)), false, id .. " is not a starter plan")
		end
		t.eq(BlueprintBook.KeyOf("ShopFront12").id, "PictureWall8")
		t.eq(BlueprintBook.KeyOf("PictureWall8"), nil)
		-- The shelf has one slot; the plan fits it.
		local slot = StoreStock.FindInShop("HearthAndHome", "PictureWall8")
		t.ok(slot ~= nil and slot.itemKind == "Blueprint", "the plan is on the General Store shelf")
		t.eq(#StoreStock.ForShop("HearthAndHome"), 20)
		t.eq(StoreStock.UnitPrice("Blueprint", "PictureWall8", false, 2), 500)
		for _, other in ipairs({ "PictureWall12", "ShopFront12" }) do
			t.eq(StoreStock.FindInShop("HearthAndHome", other), nil, other .. " is not a separate box")
		end
		-- Everything else new is a plain starter plan.
		for _, id in ipairs({
			"FlatRoofOver8",
			"FlatRoofOver12x8",
			"FlatRoofOver12",
			"Fascia8",
			"Awning8",
			"Staircase8",
			"Balcony8",
		}) do
			t.eq(BlueprintBook.IsStarter(bp(id)), true, id)
		end
	end)

	t.test("store: using the plan teaches the family; a save that knew the plan gets the new members", function()
		local book, items = {}, { { uid = "u1", id = "PictureWall8" } }
		t.eq({ BlueprintBook.Allowed("ShopFront12", false, 0, true) }, { false, "store" })
		t.ok(string.find(BlueprintBook.Message("store", bp("ShopFront12")), "Picture Window Wall plan", 1, true) ~= nil)
		local result = BlueprintBook.Redeem(book, items, "u1")
		t.eq(result, "ok")
		for _, id in ipairs(GLASS_IDS) do
			t.ok(BlueprintBook.Has(book, id), id)
			t.eq(BlueprintBook.Allowed(id, BlueprintBook.Has(book, id), 0, true), true)
		end
		t.ok(string.find(BlueprintBook.RedeemText("ok", "PictureWall8"), "5 more", 1, true) ~= nil)
		local record = { blueprintBook = { "PictureWall8" }, plot = { placed = {} } }
		BlueprintBook.Migrate(record)
		for _, id in ipairs(GLASS_IDS) do
			t.ok(BlueprintBook.Has(record.blueprintBook, id), id .. " after Migrate")
		end
		local count = #record.blueprintBook
		BlueprintBook.Migrate(record)
		t.eq(#record.blueprintBook, count, "Migrate twice changes nothing")
		-- A save that never bought the plan does not get glass for free.
		local fresh = { blueprintBook = {}, plot = { placed = {} } }
		BlueprintBook.Migrate(fresh)
		for _, id in ipairs(GLASS_IDS) do
			t.eq(BlueprintBook.Has(fresh.blueprintBook, id), false, id .. " is not given away")
		end
		for _, id in ipairs({ "Staircase8", "Balcony8", "FlatRoofOver8", "Fascia8" }) do
			t.ok(BlueprintBook.Has(fresh.blueprintBook, id), id .. " is a starter")
		end
	end)

	t.test("store: the key plan pays its kit fee on every place and sells back like a kit piece", function()
		local key = bp("PictureWall8")
		t.eq(PlotLogic.FreeToPlace(key), false)
		t.eq(PlotLogic.FreeToPlace(bp("Shed")), true)
		t.eq(PlotLogic.Source(key, 0, false, true), "store")
		t.eq(PlotLogic.Source(key, 0, true, true), "fee")
		t.eq(PlotLogic.PlacePrice(key, false), nil)
		t.eq(PlotLogic.PlacePrice(key, true), 20)
		t.eq(PlotLogic.PlacePrice(bp("Shed"), true), 0)
		t.eq(PlotLogic.SellPlan(key, { uid = "a", paid = 20 }).cash, 10)
		local row = BlueprintBook.Row(
			{ id = "PictureWall8", bp = key, group = "Buildings", stock = 0 },
			{ tier = 1, cash = 1000, boxed = true }
		)
		t.eq(row.button, "Place $20")
	end)

	---------------------------------------------------------------------
	-- Roofs, stairs, balcony, storeys
	---------------------------------------------------------------------

	t.test("roofs: an overhang roof sticks out 1.5 and the overlap test ignores exactly that", function()
		for id, size in pairs({ FlatRoofOver8 = { 8, 8 }, FlatRoofOver12x8 = { 12, 8 }, FlatRoofOver12 = { 12, 12 } }) do
			local piece = bp(id)
			t.eq(piece.overhang, 1.5)
			t.eq(piece.roof, true)
			local base = piece.boxes[1]
			t.eq({ base.size.X, base.size.Z }, { size[1] + 3, size[2] + 3 }, id .. " 1.5 each side")
			t.eq(base.role, "Edge", id .. " dark edge")
			local effective = PlotLogic.OverlapBox(piece, base)
			t.eq({ effective.size.X, effective.size.Z }, { size[1], size[2] }, id .. " overlap is the footprint")
		end
		-- Side by side, touching: allowed. Overlapping the footprint: not.
		local one = { { uid = "r", blueprintId = "FlatRoofOver8", x = 0, z = 0, rot = 0, y = 6.4 } }
		t.eq(PlotLogic.Check(bp("FlatRoofOver8"), 8, 0, 0, 1, one, nil, 6.4), true)
		t.eq(PlotLogic.Check(bp("FlatRoofOver8"), 6, 0, 0, 1, one, nil, 6.4), false)
		-- The old roof keeps its half-stud overhang.
		t.eq(PlotLogic.OverlapBox(bp("FlatRoof8"), bp("FlatRoof8").boxes[1]).size.X, 8)
	end)

	t.test("roofs: the roof edge resizes on the 2-stud grid like a beam", function()
		t.eq(PieceSize.CanResize("Fascia8"), true)
		t.eq(PieceSize.Units(bp("Fascia8"), { len = 16 }), 4)
		t.eq(PieceSize.Units(bp("Fascia8"), { len = 4 }), 1)
		t.eq(PieceSize.Shape(bp("Fascia8"), { len = 12 }).boxes[1].size.X, 12)
	end)

	t.test("stairs: eight real steps a Humanoid walks, 6.4 studs, one storey", function()
		local stairs = bp("Staircase8")
		t.eq(#stairs.boxes, ModernKit.StairSteps)
		t.eq(stairs.footprint, t.roblox.Vector2.new(4, 8))
		local lastTop, lastEnd = 0, -stairs.footprint.Y / 2
		for i, box in ipairs(stairs.boxes) do
			local top = box.offset.Y + box.size.Y / 2
			local bottom = box.offset.Y - box.size.Y / 2
			local run = box.size.Z
			t.ok(math.abs(bottom) < 1e-6, "step " .. i .. " is solid to the floor (nothing to slide under)")
			t.ok(top - lastTop <= ModernKit.MaxStepRise + 1e-6, "step " .. i .. " rise " .. (top - lastTop))
			t.ok(math.abs(top - lastTop - ModernKit.StairRise) < 1e-6, "step " .. i .. " is even")
			t.ok(run >= ModernKit.MinStepRun - 1e-6, "step " .. i .. " run")
			t.ok(math.abs((box.offset.Z - run / 2) - lastEnd) < 1e-6, "step " .. i .. " starts where the last one ends")
			t.ok(box.size.X >= 3.5, "wide enough for a character")
			t.ok(onGrid(top), "step top on the 0.2 grid")
			lastTop, lastEnd = top, box.offset.Z + run / 2
		end
		t.ok(math.abs(lastTop - ModernKit.StoreyHeight) < 1e-6, "rises exactly one storey: " .. lastTop)
		t.eq(ModernKit.StoreyHeight, 0.4 + ModernKit.WallHeight, "a floor slab and a wall")
		local pitch = math.deg(math.atan(ModernKit.StairRise / ModernKit.StairRun))
		t.ok(pitch <= ModernKit.MaxStairPitch, "pitch " .. pitch)
		t.ok(pitch < 89, "well under the default Humanoid.MaxSlopeAngle")
		t.ok(ModernKit.StairRise <= 1, "a Humanoid steps up a stud without a jump")
		t.ok(math.abs(lastEnd - stairs.footprint.Y / 2) < 1e-6, "the top step is the back edge")
	end)

	t.test("stairs: a second storey stacks floor on walls on floor, to the 0.2 grid, under the height limit", function()
		local items = {
			{ uid = "f0", blueprintId = "Floor", x = 0, z = 0, rot = 0, lenX = 12, lenZ = 12 },
			{ uid = "w0", blueprintId = "Wall12", x = 0, z = -6, rot = 0, y = 0.4 },
			{ uid = "f1", blueprintId = "Floor", x = 0, z = 0, rot = 0, y = 6.4, lenX = 12, lenZ = 12 },
			{ uid = "w1", blueprintId = "Wall12", x = 0, z = -6, rot = 0, y = 6.8 },
			{ uid = "r", blueprintId = "FlatRoofOver12", x = 0, z = 0, rot = 0, y = 12.8 },
		}
		local ok, why, which = SampleBuilds.Fits(items, 1, {}, nil)
		t.ok(ok, tostring(why) .. " at " .. tostring(which))
		for _, y in ipairs({ 0.4, 6.4, 6.8, 12.8 }) do
			t.eq(PlotLogic.HeightOk(y), true, "y " .. y)
		end
		t.eq(PlotLogic.HeightOk(6.5), false, "off the grid")
		-- A wall cannot start inside the floor under it, and the top of the build is capped.
		t.eq(PlotLogic.Check(bp("Wall12"), 0, -6, 0, 1, { items[1] }, nil, 0), false)
		t.eq(PlotLogic.Check(bp("Wall12"), 0, -6, 0, 1, { items[1] }, nil, 0.4), true)
		t.eq(PlotLogic.Check(bp("Floor4"), 20, 20, 0, 1, {}, nil, PlotData.MaxBuildY), true)
		t.eq(PlotLogic.Check(bp("Floor4"), 20, 20, 0, 1, {}, nil, PlotData.MaxBuildY + 0.2), false)
		-- Stairs stand on a floor and clear of a wall beside them.
		local stairsOnFloor = { items[1] }
		t.eq(PlotLogic.Check(bp("Staircase8"), 0, 0, 0, 1, stairsOnFloor, nil, 0.4), true)
		t.eq(PlotLogic.Check(bp("Staircase8"), 0, 0, 0, 1, stairsOnFloor, nil, 0), false, "not through the floor")
		-- The real steps let a piece sit over the low steps (a wedge's box would not).
		t.eq(
			PlotLogic.Check(
				bp("Floor4"),
				0,
				-2,
				0,
				1,
				{ { uid = "s", blueprintId = "Staircase8", x = 0, z = 0, rot = 0, y = 0.4 } },
				nil,
				4.4
			),
			true
		)
	end)

	t.test("balcony: a slab on the 0.2 grid with a railing on three sides, open to the house", function()
		local balcony = bp("Balcony8")
		local slab = balcony.boxes[1]
		t.eq(slab.size, t.roblox.Vector3.new(8, 0.4, 4))
		t.ok(onGrid(slab.size.Y))
		t.eq(#balcony.boxes, 4)
		for i = 2, 4 do
			local rail = balcony.boxes[i]
			t.ok(rail.offset.Y - rail.size.Y / 2 >= slab.size.Y - 1e-6, "rail " .. i .. " stands on the slab")
			t.ok(rail.size.Y >= 3 - 1e-6, "a railing is 3 studs")
			t.ok(
				rail.offset.Z + rail.size.Z / 2 <= balcony.footprint.Y / 2 - 0.5 + 1e-6,
				"the end rails stop short of the wall"
			)
		end
		t.ok(balcony.boxes[2].offset.Z < 0, "the front rail is on the -Z side")
		for _, y in ipairs({ 6.4, 12.8, 0.4 }) do
			t.eq(PlotLogic.Check(balcony, 0, -10, 0, 1, {}, nil, y), true, "y " .. y)
		end
		t.eq(PlotLogic.Check(balcony, 0, -10, 0, 1, {}, nil, 6.5), false, "off the height grid")
		-- Against the upstairs front wall, on the upstairs floor edge.
		local house = {
			{ uid = "f", blueprintId = "Floor", x = 0, z = 0, rot = 0, y = 6.4, lenX = 12, lenZ = 12 },
			{ uid = "w", blueprintId = "GlassDoorWall8", x = -2, z = -6, rot = 0, y = 6.8 },
		}
		t.eq(PlotLogic.Check(balcony, -2, -8, 0, 1, house, nil, 6.4), true)
	end)

	---------------------------------------------------------------------
	-- The samples
	---------------------------------------------------------------------

	local function uid(i)
		return "s" .. i
	end

	t.test("samples: modern, shop and barn each pass PlotLogic.Check on an empty plot, at every turn", function()
		t.eq(SampleBuilds.List, { "modern", "shop", "barn" })
		for _, name in ipairs(SampleBuilds.List) do
			local sample = SampleBuilds.Get(name)
			t.ok(sample ~= nil, name)
			for rot = 0, 3 do
				local items = SampleBuilds.Items(sample, rot, 0, 0, uid)
				t.eq(#items, #sample.pieces)
				local ok, why, which = SampleBuilds.Fits(items, 1, {}, nil)
				t.ok(ok, string.format("%s rot %d: %s at %s", name, rot, tostring(why), tostring(which)))
			end
			t.eq(SampleBuilds.Get(string.upper(name)), sample, "names are not case sensitive")
		end
		t.eq(SampleBuilds.Get("castle"), nil)
		t.eq(SampleBuilds.Get(5), nil)
	end)

	t.test("samples: pieces are real, on the grid, free and built, and the kit caps hold", function()
		for _, name in ipairs(SampleBuilds.List) do
			local sample = SampleBuilds.Get(name)
			local kit, other = SampleBuilds.Counts(sample)
			t.ok(kit <= PlotData.MaxKit and other <= PlotData.MaxItems, name .. " fits the caps")
			t.ok(kit >= 8, name .. " is a real building")
			for rot = 0, 3 do
				for i, item in ipairs(SampleBuilds.Items(sample, rot, 0, 0, uid)) do
					local piece = bp(item.blueprintId)
					t.ok(piece ~= nil, name .. " piece " .. i)
					t.eq(item.x % 2, 0, name .. " x on the 2-stud grid")
					t.eq(item.z % 2, 0, name .. " z on the 2-stud grid")
					t.ok(PlotLogic.HeightOk(item.y or 0), name .. " height " .. tostring(item.y))
					if piece.kit then
						t.eq(item.paid, 0, "free: a sample piece sells for nothing")
						t.eq(item.fill, nil, "and is already built")
						t.ok(item.wood ~= nil)
						t.eq(PlotLogic.SellPlan(piece, item).cash, 0)
						if item.paint then
							t.eq(KitPaint.Valid(item.paint), true, name .. " paint " .. item.paint)
						end
					else
						t.eq(piece.unlock, true, name .. " only uses a decor piece that sells for nothing")
					end
				end
			end
		end
		local items = SampleBuilds.Items(SampleBuilds.Get("modern"), 0, 0, 0, uid)
		for _, item in ipairs(items) do
			if item.blueprintId == "Floor" then
				t.ok(item.lenX ~= nil and item.lenZ ~= nil)
				t.eq(PieceSize.LengthOk(8, item.lenX), true)
				t.eq(PieceSize.LengthOk(8, item.lenZ), true)
			end
		end
	end)

	t.test("samples: the modern house has two storeys, glass, stairs, a balcony and an overhanging roof", function()
		local have = {}
		local top = 0
		for _, piece in ipairs(SampleBuilds.Get("modern").pieces) do
			have[piece.id] = (have[piece.id] or 0) + 1
			top = math.max(top, piece.y or 0)
		end
		for _, id in ipairs({ "PictureWall12", "GlassDoorWall8", "Door", "Staircase8", "Balcony8", "FlatRoofOver12x8" }) do
			t.ok(have[id], id)
		end
		t.ok(top >= 12.8, "two storeys and a roof")
		local shop = {}
		for _, piece in ipairs(SampleBuilds.Get("shop").pieces) do
			shop[piece.id] = true
		end
		for _, id in ipairs({ "ShopFront12", "Awning8", "Fascia8", "WoodSign" }) do
			t.ok(shop[id], "the shop has " .. id)
		end
		for _, piece in ipairs(SampleBuilds.Get("barn").pieces) do
			local def = bp(piece.id)
			t.ok(not ModernKit.ById[piece.id], "the barn uses only older pieces: " .. piece.id)
			t.ok(def ~= nil)
		end
	end)

	t.test("samples: a sample is turned to face whoever aimed it, and its centre goes where they aimed", function()
		t.eq(SampleBuilds.FacingRot(0, 1), 0, "looking +Z at it: its front (-Z) already faces you")
		t.eq(SampleBuilds.FacingRot(0, -1), 2)
		t.eq(SampleBuilds.FacingRot(1, 0), 1)
		t.eq(SampleBuilds.FacingRot(-1, 0), 3)
		local items = SampleBuilds.Items(SampleBuilds.Get("shop"), 0, 21, -9, uid)
		t.eq(items[1].x, 22)
		t.eq(items[1].z, -8)
		t.eq(items[1].uid, "s1")
	end)

	t.test("samples: it finds another spot when the aimed one is taken, and refuses when there is none", function()
		local sample = SampleBuilds.Get("shop")
		local blocker = { uid = "b", blueprintId = "Foundation8", x = 0, z = 0, rot = 0 }
		local items = SampleBuilds.Find(sample, 0, 0, 0, 1, { blocker }, nil, uid)
		t.ok(items ~= nil, "a free spot nearby")
		local ok = SampleBuilds.Fits(items, 1, { blocker }, nil)
		t.eq(ok, true)
		local none, why = SampleBuilds.Find(sample, 0, 500, 500, 1, {}, nil, uid)
		t.eq(none, nil, "off the plot")
		t.ok(why ~= nil)
		-- The kit cap counts what is already there.
		local crowded = {}
		for i = 1, PlotData.MaxKit do
			table.insert(crowded, {
				uid = "k" .. i,
				blueprintId = "Post",
				x = -38 + (i % 40) * 2,
				z = -38 + math.floor(i / 40) * 2,
				rot = 0,
			})
		end
		local capped, capWhy = SampleBuilds.Find(sample, 0, 0, 0, 1, crowded, nil, uid)
		t.eq(capped, nil)
		t.ok(capWhy ~= nil)
		t.eq(SampleBuilds.IsSampleUid("sample-1"), true)
		t.eq(SampleBuilds.IsSampleUid("abc"), false)
		t.eq(SampleBuilds.IsSampleUid(nil), false)
	end)

	t.test("samples: /sample is owner only. It is on no role's list, so nobody can be given it", function()
		t.ok(table.find(AdminLogic.NeverDelegable, "sample") ~= nil)
		t.eq(table.find(AdminLogic.AllPowers, "sample"), nil, "not even TESTER holds it")
		t.eq(table.find(AdminLogic.DelegablePowers, "sample"), nil)
		for role, powers in pairs(AdminLogic.Roles) do
			t.eq(table.find(powers, "sample"), nil, role)
		end
		for _, grant in ipairs({
			{ role = "TESTER", powers = AdminLogic.AllPowers },
			{ role = "CUSTOM", powers = { "sample", "gift", "goto" } },
			{ role = "BUILDER", powers = AdminLogic.Roles.BUILDER },
			{ role = "MODERATOR", powers = AdminLogic.Roles.MODERATOR },
		}) do
			t.eq((AdminLogic.GrantAllows(grant, "sample")), false, grant.role)
		end
		local found = false
		for _, line in ipairs(AdminLogic.Help) do
			if string.find(line, "/sample", 1, true) then
				found = true
			end
		end
		t.ok(found, "the help lists it")
		t.eq(AdminLogic.Parse("/sample modern").name, "sample")
		t.eq(AdminLogic.Parse("/sample modern").args[1], "modern")
	end)
end
