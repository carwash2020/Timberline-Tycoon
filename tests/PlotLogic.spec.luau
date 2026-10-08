--!nocheck
-- Plots: where the district is, the base tiers, the blueprints, and where
-- a blueprint may go (Shared/PlotData, Shared/PlotLogic).
return function(t)
	local PlotData = t.shared("PlotData")
	local PlotLogic = t.shared("PlotLogic")
	local BiomeData = t.shared("BiomeData")

	local MAX = PlotData.Tiers[#PlotData.Tiers].size

	local function rectsOverlap(ax, az, aw, ad, bx, bz, bw, bd)
		return math.abs(ax - bx) * 2 < aw + bw and math.abs(az - bz) * 2 < ad + bd
	end

	-- Closest distance from a circle's centre to a square plot.
	local function circleHitsSquare(cx, cz, r, sx, sz, size)
		local dx = math.max(math.abs(cx - sx) - size / 2, 0)
		local dz = math.max(math.abs(cz - sz) - size / 2, 0)
		return dx * dx + dz * dz < r * r
	end

	t.test("homesteads: a shelf, a lane and a delivery pad for every player plus two", function()
		local GameConfig = t.shared("GameConfig")
		local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
		local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
		local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
		local ItemCatalog = t.shared("ItemCatalog")
		t.eq(#PlotData.Homes, GameConfig.MaxPlayers + 2)
		t.eq(#PlotData.Slots, PlotData.Count)
		t.eq(PlotData.Pad, 200)
		t.ok(PlotData.Blend >= 50, "blend " .. PlotData.Blend)
		t.ok(PlotData.LaneWidth >= 22, "lane " .. PlotData.LaneWidth)
		local rig = ItemCatalog.Trucks.LoggingRig
		local hauler = ItemCatalog.Trailers.HeavyHauler
		t.ok(PlotData.LaneWidth >= rig.look.width + 8, "a Logging Rig fits the lane")
		t.ok(PlotData.DeliveryWidth >= rig.look.width + 4, "the delivery pad is wider than the rig")
		t.ok(
			PlotData.DeliveryLength >= rig.look.bedLength + hauler.look.bedLength + 12,
			"the delivery pad holds a rig plus a Heavy Hauler"
		)
		local regions = {}
		for _, home in ipairs(PlotData.Homes) do
			regions[home.region] = true
			t.ok(#home.name > 0 and #home.region > 0, home.id)
		end
		local kinds = 0
		for _ in pairs(regions) do
			kinds += 1
		end
		t.ok(kinds >= 4, kinds .. " different stretches of country")
		t.ok(regions["Starter Forest"] and regions["The Hills"], "starter and the hills both have a pad")
		-- The picker opens in the Starter Forest. The timeout takes that same
		-- first free pad.
		local PlotPickerLogic = t.shared("PlotPickerLogic")
		local first = PlotData.Homes[1]
		t.eq(first.region, "Starter Forest")
		t.eq(first.name, "Birch Side")
		t.eq(PlotData.Homes[2].name, "Orchard Edge")
		t.eq(PlotData.Homes[2].region, "Starter Forest")
		t.eq(PlotData.Homes[3].name, "Oak Side")
		t.eq(PlotData.Homes[3].region, "Starter Forest")
		t.eq(PlotData.Homes[4].name, "The Climb")
		local open = {}
		for i = 1, #PlotData.Homes do
			open[i] = false
		end
		local free = PlotPickerLogic.FirstFree(open)
		t.eq(PlotData.Homes[free].region, "Starter Forest")
		-- East Meadow stays east of the display lot, south of the path.
		local meadow = nil
		for _, home in ipairs(PlotData.Homes) do
			if home.name == "East Meadow" then
				meadow = home
			end
		end
		t.ok(meadow ~= nil)
		t.ok(meadow.x > 296 and meadow.z > -140 and meadow.z < 80, "east of the display lot")
		local sawForOrder = WorldLayout.Sawmill
		local function haulOf(home)
			return math.sqrt((home.x - sawForOrder.X) ^ 2 + (home.z - sawForOrder.Z) ^ 2)
		end
		for i = 5, #PlotData.Homes - 1 do
			t.ok(
				haulOf(PlotData.Homes[i]) <= haulOf(PlotData.Homes[i + 1]) + 1e-4,
				PlotData.Homes[i].name .. " is listed before a nearer home"
			)
		end
		for _, zone in ipairs(WorldLayout.FlatZones) do
			-- Town, and the display lot's own flat patch, are the town job's
			-- ground. Shelves and the apron still stay clear of both reserved boxes.
			if zone.name ~= "Town" and zone.name ~= "DealershipLot" then
				for _, box in ipairs(WorldLayout.Reserved) do
					local gap = WorldLayout.ReservedDistance(zone.x0, zone.z0, zone.x1, zone.z1, box)
					local need = zone.blend
					-- The Climb's blend clears the display lot (the edge at
					-- z 123) by at least 10 studs, not only by the blend.
					for _, home in ipairs(PlotData.Homes) do
						if home.name == "The Climb" and zone.cx == home.x and zone.cz == home.z then
							need += 10
						end
					end
					t.ok(
						gap >= need,
						string.format("%s comes within %.0f of %s (need %d)", zone.name, gap, box.name, need)
					)
				end
			end
		end
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "PlotSpur" then
				local pts = road.points
				local reach = PlotData.LaneWidth / 2
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = (b - a).Magnitude
					local steps = math.max(1, math.ceil(len / 4))
					for s = 0, steps do
						local p = a:Lerp(b, s / steps)
						for _, box in ipairs(WorldLayout.Reserved) do
							local dx = math.max(box.x0 - p.X, 0, p.X - box.x1)
							local dz = math.max(box.z0 - p.Y, 0, p.Y - box.z1)
							t.ok(dx * dx + dz * dz >= reach * reach, string.format("a lane crosses %s", box.name))
						end
					end
				end
			end
		end
		local saw = WorldLayout.Sawmill
		local nearCount = 0
		for i, home in ipairs(PlotData.Homes) do
			local haul = math.sqrt((home.x - saw.X) ^ 2 + (home.z - saw.Z) ^ 2)
			if i <= 6 then
				if haul <= PlotData.NearHaul then
					nearCount += 1
				end
			else
				t.ok(haul > PlotData.NearHaul, home.name .. " is one of the further homes")
			end
		end
		t.ok(nearCount >= 4 and nearCount <= 6, nearCount .. " homes within a short haul, listed first")
		local harsh = { snow = true, volcano = true, grove = true }
		for i, home in ipairs(PlotData.Homes) do
			local haul = math.sqrt((home.x - saw.X) ^ 2 + (home.z - saw.Z) ^ 2)
			t.ok(haul < 800, string.format("%s is %.0f studs from town", home.name, haul))
			t.eq(TerrainGen.WaterLevelAt(home.x, home.z), nil, home.name .. " is dry")
			local h = TerrainGen.HeightAt(home.x, home.z)
			local lo, hi = h, h
			for x = -80, 80, 40 do
				for z = -80, 80, 40 do
					local sample = TerrainGen.HeightAt(home.x + x, home.z + z)
					lo, hi = math.min(lo, sample), math.max(hi, sample)
				end
			end
			t.ok(hi - lo < 1, string.format("%s shelf varies by %.2f", home.name, hi - lo))
			local grove = math.huge
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and (biome.id == "starter" or biome.id == "hills" or biome.id == "grove") then
					local d = math.sqrt((home.x - area.x) ^ 2 + (home.z - area.z) ^ 2) - area.radius
					grove = math.min(grove, math.max(0, d))
				end
			end
			t.ok(grove <= PlotData.GroveReach, string.format("%s is %.0f from a grove", home.name, grove))
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and harsh[biome.id] then
					local dx, dz = home.x - area.x, home.z - area.z
					t.ok(
						dx * dx + dz * dz > (area.radius + MAX / 2) ^ 2,
						string.format("%s sits in %s", home.name, biome.id)
					)
				end
			end
			for j = 1, 322 do
				local tree = WorldPlan.Trees()[j]
				local dx, dz = tree.position.X - home.x, tree.position.Z - home.z
				t.ok(
					math.max(math.abs(dx), math.abs(dz)) > MAX / 2,
					string.format("saved tree %d stands on %s", j, home.name)
				)
			end
		end
		local zones = 0
		for _, zone in ipairs(WorldLayout.FlatZones) do
			if zone.name == "Plot" then
				zones += 1
				t.eq(zone.x1 - zone.x0, PlotData.Pad)
				t.eq(zone.z1 - zone.z0, PlotData.Pad)
				t.ok(zone.blend >= 50, "blend " .. tostring(zone.blend))
			end
		end
		t.eq(zones, PlotData.Count)
		local function hits(sx, sz, size, ax, az, bx, bz, width)
			local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
			local steps = math.max(1, math.ceil(len / 4))
			local reach = width / 2
			for i = 0, steps do
				local u = i / steps
				local x, z = ax + (bx - ax) * u, az + (bz - az) * u
				local dx = math.max(math.abs(x - sx) - size / 2, 0)
				local dz = math.max(math.abs(z - sz) - size / 2, 0)
				if dx * dx + dz * dz < (reach - 0.5) ^ 2 then
					return true
				end
			end
			return false
		end
		local function nearLane(sx, sz)
			local best = math.huge
			for _, road in ipairs(WorldLayout.Roads) do
				if road.name == "PlotSpur" then
					local pts = road.points
					for i = 1, #pts - 1 do
						local a, b = pts[i], pts[i + 1]
						local len = math.sqrt((b.X - a.X) ^ 2 + (b.Y - a.Y) ^ 2)
						local steps = math.max(1, math.ceil(len / 8))
						for s = 0, steps do
							local u = s / steps
							local x = a.X + (b.X - a.X) * u
							local z = a.Y + (b.Y - a.Y) * u
							local dx = math.max(math.abs(x - sx) - MAX / 2, 0)
							local dz = math.max(math.abs(z - sz) - MAX / 2, 0)
							best = math.min(best, math.sqrt(dx * dx + dz * dz))
						end
					end
				end
			end
			return best
		end
		for i, slot in ipairs(PlotData.Slots) do
			t.ok(nearLane(slot.X, slot.Y) <= PlotData.LaneWidth + 8, "plot " .. i .. " meets a road")
			local drive = WorldLayout.Drives[i]
			t.ok(drive ~= nil, "plot " .. i .. " has a delivery pad")
			if drive then
				local dx = math.abs(drive.x - slot.X)
				local dz = math.abs(drive.z - slot.Y)
				t.ok(dx <= MAX / 2 and dz <= MAX / 2, "delivery pad sits on the yard")
				t.eq(TerrainGen.WaterLevelAt(drive.x, drive.z), nil, "delivery pad is dry")
				local halfL, halfW = PlotData.DeliveryLength / 2, PlotData.DeliveryWidth / 2
				local tx, tz = -drive.uz, drive.ux
				for _, corner in ipairs({
					{ drive.ux * halfW + tx * halfL, drive.uz * halfW + tz * halfL },
					{ drive.ux * halfW - tx * halfL, drive.uz * halfW - tz * halfL },
					{ -drive.ux * halfW + tx * halfL, -drive.uz * halfW + tz * halfL },
					{ -drive.ux * halfW - tx * halfL, -drive.uz * halfW - tz * halfL },
				}) do
					local x, z = drive.x + corner[1], drive.z + corner[2]
					t.eq(TerrainGen.WaterLevelAt(x, z), nil, "delivery corner is dry")
					t.ok(
						math.abs(x - slot.X) <= MAX / 2 + 1 and math.abs(z - slot.Y) <= MAX / 2 + 1,
						"delivery stays on the pad"
					)
				end
			end
			for _, road in ipairs(WorldLayout.Roads) do
				local pts = road.points
				for s = 1, #pts - 1 do
					local a, b = pts[s], pts[s + 1]
					t.ok(
						not hits(slot.X, slot.Y, MAX, a.X, a.Y, b.X, b.Y, road.width),
						string.format("plot %d overlaps %s", i, road.name)
					)
				end
			end
		end
	end)

	t.test("the district has a slot per player, apart even at the biggest tier", function()
		t.ok(#PlotData.Slots >= 12, "a full server (12) needs 12 plots")
		for i, a in ipairs(PlotData.Slots) do
			for j, b in ipairs(PlotData.Slots) do
				if i < j then
					local apart = math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2)
					local axis = math.max(math.abs(a.X - b.X), math.abs(a.Y - b.Y)) - PlotData.Pad
					t.ok(
						axis >= PlotData.MinSpacing - PlotData.Pad,
						string.format("plots %d and %d have %.0f studs between shelves", i, j, axis)
					)
					t.ok(apart >= PlotData.MinSpacing, string.format("plots %d and %d are %.0f apart", i, j, apart))
					t.ok(
						not rectsOverlap(a.X, a.Y, MAX, MAX, b.X, b.Y, MAX, MAX),
						string.format("plots %d and %d share ground", i, j)
					)
				end
			end
		end
	end)

	t.test("homesteads stay out of town and inside the world", function()
		for i, slot in ipairs(PlotData.Slots) do
			for _, biome in ipairs(BiomeData.All()) do
				local area = biome.area
				if area and area.y == nil then -- the isles float far above
					t.ok(
						not circleHitsSquare(area.x, area.z, area.radius, slot.X, slot.Y, MAX),
						string.format("plot %d runs into %s", i, biome.id)
					)
				end
			end
			-- Town: sawmill, shops, spawn, parking lot and gondola station.
			t.ok(not rectsOverlap(slot.X, slot.Y, MAX, MAX, 0, 90, 260, 220), string.format("plot %d is in town", i))
			t.ok(math.abs(slot.X) + MAX / 2 < 1480 and math.abs(slot.Y) + MAX / 2 < 1480, "inside the world")
		end
	end)

	t.test("base tiers start free and grow in size and price", function()
		t.eq(PlotData.Tiers[1].priceCash, 0)
		t.eq(PlotData.Tiers[1].size, 80) -- GAME_DESIGN §10
		t.eq(MAX, 200)
		for i = 2, #PlotData.Tiers do
			local a, b = PlotData.Tiers[i - 1], PlotData.Tiers[i]
			t.ok(b.size > a.size, b.name .. " must be bigger")
			t.ok(b.priceCash > a.priceCash, b.name .. " must cost more")
		end
	end)

	t.test("every blueprint is well formed and fits a Campsite", function()
		local seen = {}
		for _, bp in ipairs(PlotData.Blueprints) do
			t.ok(not seen[bp.id], "duplicate blueprint " .. bp.id)
			seen[bp.id] = true
			t.eq(PlotData.Blueprint(bp.id), bp)
			t.ok(bp.category == "Buildings" or bp.category == "Decor", bp.id .. " category")
			t.ok(PlotData.Tier(bp.tier) ~= nil, bp.id .. " tier")
			t.ok(bp.priceCash > 0, bp.id .. " price")
			t.ok(bp.footprint.X <= PlotData.Tiers[1].size and bp.footprint.Y <= PlotData.Tiers[1].size)
			t.ok(#bp.boxes > 0, bp.id .. " has no parts")
			for i, box in ipairs(bp.boxes) do
				local where = string.format("%s box %d", bp.id, i)
				t.ok(
					pcall(function()
						return t.roblox.Enum.Material[box.material]
					end),
					where .. " material"
				)
				t.ok(string.match(box.color, "^#%x%x%x%x%x%x$") ~= nil, where .. " color")
				-- Inside the footprint (a roof may overhang by a stud).
				t.ok(
					math.abs(box.offset.X) + box.size.X / 2 <= bp.footprint.X / 2 + (bp.overhang or 1),
					where .. " sticks out in x"
				)
				t.ok(
					math.abs(box.offset.Z) + box.size.Z / 2 <= bp.footprint.Y / 2 + (bp.overhang or 1),
					where .. " sticks out in z"
				)
				t.ok(box.offset.Y - box.size.Y / 2 >= -0.01, where .. " is under the ground")
			end
		end
	end)

	t.test("a quarter turn swaps width and depth", function()
		local fence = PlotData.Blueprint("Fence")
		t.eq({ PlotLogic.Footprint(fence, 0) }, { 8, 1 })
		t.eq({ PlotLogic.Footprint(fence, 1) }, { 1, 8 })
		t.eq({ PlotLogic.Footprint(fence, 2) }, { 8, 1 })
		t.eq({ PlotLogic.Footprint(fence, 3) }, { 1, 8 })
	end)

	t.test("positions snap to the grid", function()
		t.eq(PlotData.Grid, 2) -- GAME_DESIGN §14.6
		t.eq(PlotLogic.Snap(0.9), 0)
		t.eq(PlotLogic.Snap(1.1), 2)
		t.eq(PlotLogic.Snap(-3.2), -4)
		t.eq(PlotLogic.Snap(10), 10)
	end)

	t.test("things must fit inside the plot", function()
		local cabin = PlotData.Blueprint("Cabin") -- 12 x 10
		t.ok((PlotLogic.Check(cabin, 34, 35, 0, 1, {})), "edge to edge with the plot is fine")
		local ok, why = PlotLogic.Check(cabin, 36, 0, 0, 1, {})
		t.ok(not ok)
		t.eq(why, "Outside your plot")
		t.ok((PlotLogic.Check(cabin, 49, 0, 0, 2, {})), "a Homestead (110) has room")
		t.ok(not (PlotLogic.Check(cabin, 0, 35, 1, 1, {})), "turned, it's 12 deep")
	end)

	t.test("things can't overlap, but may touch", function()
		local fence = PlotData.Blueprint("Fence")
		local placed = { { uid = "a", blueprintId = "Fence", x = 0, z = 0, rot = 0 } }
		t.ok((PlotLogic.Check(fence, 8, 0, 0, 1, placed)), "end to end")
		t.ok((PlotLogic.Check(fence, 0, 2, 0, 1, placed)), "side by side")
		local ok, why = PlotLogic.Check(fence, 4, 0, 0, 1, placed)
		t.ok(not ok)
		t.eq(why, "Something's in the way")
		t.ok(not (PlotLogic.Check(fence, 0, 0, 1, 1, placed)), "crossing it")
		t.ok((PlotLogic.Check(fence, 4, 0, 0, 1, placed, "a")), "moving the fence itself")
	end)

	t.test("blueprints wait for the tier that unlocks them", function()
		local warehouse = PlotData.Blueprint("Warehouse")
		local ok, why = PlotLogic.Check(warehouse, 0, 0, 0, 1, {})
		t.ok(not ok)
		t.eq(why, "Needs a Homestead plot")
		t.ok((PlotLogic.Check(warehouse, 0, 0, 0, 2, {})))
	end)

	t.test("a plot holds MaxItems things", function()
		local placed = {}
		for i = 1, PlotData.MaxItems do
			placed[i] = { uid = tostring(i), blueprintId = "Unknown", x = 0, z = 0, rot = 0 }
		end
		local flag = PlotData.Blueprint("Flag")
		t.ok(not (PlotLogic.Check(flag, 20, 20, 0, 1, placed)))
		t.ok((PlotLogic.Check(flag, 20, 20, 0, 1, placed, "1")), "moving one of them is fine")
	end)

	t.test("placing stops at PlacedCap; moving a piece already there does not", function()
		local GameConfig = t.shared("GameConfig")
		local placed = {}
		for i = 1, GameConfig.PlacedCap do
			placed[i] = { uid = "u" .. i, blueprintId = "Wall", x = i * 1000, z = 0, rot = 0 }
		end
		local wall = PlotData.Blueprint("Wall")
		local ok, why = PlotLogic.Check(wall, 4, 4, 0, #PlotData.Tiers, placed)
		t.eq(ok, false)
		t.ok(string.find(why, "placed pieces", 1, true) ~= nil, why)
		t.eq(PlotLogic.Check(wall, 4, 4, 0, #PlotData.Tiers, placed, "u1"), true)
	end)

	t.test("nonsense positions and turns are refused", function()
		local flag = PlotData.Blueprint("Flag")
		for _, rot in ipairs({ -1, 4, 0.5 }) do
			t.eq({ PlotLogic.Check(flag, 0, 0, rot, 1, {}) }, { false, "bad" })
		end
		t.eq({ PlotLogic.Check(flag, 0 / 0, 0, 0, 1, {}) }, { false, "bad" })
		t.ok(not (PlotLogic.Check(flag, math.huge, 0, 0, 1, {})))
		t.eq({ PlotLogic.Check(flag, 0, 0, 0, 99, {}) }, { false, "bad" })
	end)

	t.test("selling back pays half, rounded down", function()
		t.eq(PlotData.SellBack, 0.5)
		t.eq(PlotLogic.SellValue(PlotData.Blueprint("Cabin")), 1000)
		t.eq(PlotLogic.SellValue({ priceCash = 45 }), 22)
	end)

	t.test("the Land panel's plot size card names the level, the next size and what it unlocks", function()
		local first = PlotLogic.SizeCard(1, 0)
		t.eq(first.level, 1)
		t.eq(first.levels, #PlotData.Tiers)
		t.eq(first.size, PlotData.Tiers[1].size)
		t.ok(first.next ~= nil)
		t.eq(first.next.name, PlotData.Tiers[2].name)
		t.eq(first.next.price, PlotData.Tiers[2].priceCash)
		t.eq(first.next.affordable, false)
		t.eq(first.next.short, PlotData.Tiers[2].priceCash)
		t.eq(PlotLogic.SizeCard(1, PlotData.Tiers[2].priceCash).next.affordable, true)
		t.eq(PlotLogic.SizeCard(1, PlotData.Tiers[2].priceCash).next.short, 0)
		local top = PlotLogic.SizeCard(#PlotData.Tiers, 0)
		t.eq(top.next, nil, "nothing past the last level")
		t.eq(PlotLogic.SizeCard(99, 0).level, #PlotData.Tiers, "clamped")
		t.eq(PlotLogic.UnlocksText(2) ~= "", true, "tier 2 unlocks blueprints")
	end)

	t.test("Land cells say whether ground was bought or came with the plot size", function()
		local half = PlotLogic.GridHalf()
		local text, kind = PlotLogic.CellLabel(1, {}, 0, 0)
		t.eq({ text, kind }, { "Plot", "included" }, "the middle comes with the plot size")
		local buy
		for ix = -half, half do
			local key = PlotLogic.ExpansionBlock(1, {}, ix, 0)
			if key then
				buy = ix
				break
			end
		end
		t.ok(buy ~= nil, "some square beside the plot is for sale")
		text, kind = PlotLogic.CellLabel(1, {}, buy, 0)
		t.eq({ text, kind }, { "Buy", "buy" })
		text, kind = PlotLogic.CellLabel(1, { PlotLogic.Key(buy, 0) }, buy, 0)
		t.eq({ text, kind }, { "Yours", "bought" })
		text, kind = PlotLogic.CellLabel(1, {}, half, half)
		t.eq(kind, "far")
	end)

	t.test("every refusal has words, in plot and expand", function()
		for _, why in ipairs({ "cash", "yours", "owned", "away", "full", "bad" }) do
			local message = PlotLogic.ExpansionMessage(why)
			t.ok(message ~= nil and not string.find(message, "yard"), why)
		end
		t.eq(PlotLogic.ExpansionMessage("nope"), nil)
	end)

	t.test("yard squares step up in price and stop at 25", function()
		local GameConfig = t.shared("GameConfig")
		t.eq(PlotLogic.ExpansionPrice(0), GameConfig.FirstPlotPrice)
		t.eq(PlotLogic.ExpansionPrice(1), GameConfig.ExpansionPriceStep)
		t.eq(PlotLogic.ExpansionPrice(24), GameConfig.ExpansionPriceStep * 24)
		t.eq(PlotLogic.ExpansionPrice(25), nil)
		local sum = 0
		for bought = 0, 24 do
			sum += PlotLogic.ExpansionPrice(bought)
		end
		local sumK = 24 * 25 / 2
		t.eq(sum, GameConfig.FirstPlotPrice + GameConfig.ExpansionPriceStep * sumK)
		t.eq(sum, 2280100)
		-- The campsite (one square, 80 wide) covers the middle. Only a square that touches it is for sale.
		t.eq({ PlotLogic.ExpansionBlock(1, {}, 0, 0) }, { nil, "yours" })
		t.eq({ PlotLogic.ExpansionBlock(1, {}, 2, 2) }, { nil, "away" })
		t.eq(PlotLogic.ExpansionBlock(1, {}, 1, 0), "1,0")
		t.eq({ PlotLogic.ExpansionBlock(#PlotData.Tiers, {}, 2, 0) }, { nil, "yours" })
		t.eq(PlotLogic.EjectLocal(120, {}), 0)
		local _, north = PlotLogic.EjectLocal(120, {})
		t.eq(north, 68)
		local eastX, eastZ = PlotLogic.EjectSpot(120, {}, function(x, z)
			return not (x > 0 and z == 0)
		end)
		t.eq(eastX, 68)
		t.eq(eastZ, 0)
		local backX, backZ = PlotLogic.EjectSpot(120, {}, function()
			return true
		end)
		t.eq(backX, 0)
		t.eq(backZ, 68)
		-- B15: more places to try, nearest first, none repeated; a spot past the
		-- first five is used when those are on a road or in the water.
		local list = PlotLogic.EjectCandidates(120, {})
		t.ok(#list > 5, "more than the first five")
		local seen = {}
		for _, spot in ipairs(list) do
			local key = spot[1] .. "," .. spot[2]
			t.ok(not seen[key], "no repeats: " .. key)
			seen[key] = true
		end
		local firstFive = 0
		local cornerX, cornerZ = PlotLogic.EjectSpot(120, {}, function(x, z)
			firstFive += 1
			return firstFive <= 5
		end)
		t.eq({ cornerX, cornerZ }, { list[6][1], list[6][2] })
		t.eq(PlotLogic.GroundBad(true, false), true)
		t.eq(PlotLogic.GroundBad(false, true), true)
		t.eq(PlotLogic.GroundBad(false, false), false)
		local WorldLayout = t.shared("World/WorldLayout")
		local road = WorldLayout.Roads[1].points[1]
		t.eq(PlotLogic.OnRoad(road.X, road.Y), true)
		t.eq(PlotLogic.OnRoad(9000, 9000), false)
		t.eq(PlotLogic.InWater(WorldLayout.Lake.x, WorldLayout.Lake.z), true)
		t.eq(PlotLogic.InWater(9000, 9000), false)
	end)

	t.test("a footprint may sit on a bought square, and not on the square beside it", function()
		local bench = PlotData.Blueprint("Bench")
		local owned = { "2,0" }
		t.eq({ PlotLogic.Check(bench, 80, 0, 0, 1, {}) }, { false, "Outside your plot" })
		t.ok((PlotLogic.Check(bench, 80, 0, 0, 1, {}, nil, 0, owned)))
		t.eq({ PlotLogic.Check(bench, 80, 40, 0, 1, {}, nil, 0, owned) }, { false, "Outside your plot" })
	end)

	t.test("expansion takes the cash only when the square is granted", function()
		local function purse(start)
			local cash = start
			local spent = 0
			local api = {}
			function api.cash()
				return cash
			end
			function api.spend(amount)
				spent += 1
				cash -= amount
				return true
			end
			function api.refund(amount)
				cash += amount
			end
			function api.read()
				return cash, spent
			end
			return api
		end

		local GameConfig = t.shared("GameConfig")
		local step = GameConfig.ExpansionPriceStep
		local short = purse(50)
		local plot = { tier = 1, squares = {} }
		local ok, why, price = PlotLogic.TryExpand(plot, 1, 0, short)
		t.eq(ok, false)
		t.eq(why, "cash")
		t.eq(price, 100)
		t.eq({ short.read() }, { 50, 0 })
		t.eq(plot.squares, {})

		local paid = purse(100)
		ok, why, price = PlotLogic.TryExpand(plot, 1, 0, paid)
		t.eq(ok, true)
		t.eq(why, nil)
		t.eq(price, 100)
		t.eq({ paid.read() }, { 0, 1 })
		t.eq(plot.squares, { "1,0" })
		-- The button price is the next deduction.
		t.eq(PlotLogic.ExpansionPrice(#plot.squares), step)

		local threw = purse(step)
		local take = threw.spend
		function threw.spend(amount)
			take(amount)
			error("spend failed after taking the cash")
		end
		local before = #plot.squares
		ok = PlotLogic.TryExpand(plot, 1, 1, threw)
		t.eq(ok, false)
		t.eq(#plot.squares, before)
		t.eq(threw.cash(), step)

		local refused = purse(step)
		local deduct = refused.spend
		function refused.spend(amount)
			deduct(amount)
			return false
		end
		ok = PlotLogic.TryExpand(plot, 2, 1, refused)
		t.eq(ok, false)
		t.eq(#plot.squares, before)
		t.eq(refused.cash(), step)
	end)

	t.test("Source: where an item behind a blueprint comes from, the palette's and the server's one rule", function()
		local function bp(id)
			return PlotLogic.Blueprint(id)
		end
		-- In stock, or an unlock you bought: place it free.
		t.eq(PlotLogic.Source(bp("SawmillRickety"), 1, false, true), "place")
		t.eq(PlotLogic.Source(bp("ChopSaw"), 2, false, true), "place")
		t.eq(PlotLogic.Source(bp("Shed"), 0, true, true), "place")
		-- A sawmill or the chop saw you don't hold is a box at the Tool Shed.
		t.eq(PlotLogic.Source(bp("SawmillRickety"), 0, false, true), "toolShed")
		t.eq(PlotLogic.Source(bp("Millmaster200L"), 0, false, true), "toolShed")
		t.eq(PlotLogic.Source(bp("ChopSaw"), 0, false, true), "toolShed")
		-- With boxed shelves off it is the old pay-as-you-place.
		t.eq(PlotLogic.Source(bp("SawmillRickety"), 0, false, false), "fee")
		t.eq(PlotLogic.Source(bp("ChopSaw"), 0, false, false), "fee")
		-- A furniture unlock you haven't bought is the General Store's box.
		t.eq(PlotLogic.Source(bp("Shed"), 0, false, true), "store")
		-- A kit piece is a placing fee, boxed shelves or not.
		t.eq(PlotLogic.Source(bp("Wall"), 0, false, true), "fee")
		t.eq(PlotLogic.Source(bp("Floor"), 0, false, false), "fee")
		-- A stocked mill that is also "unlocked" is still just placed.
		t.eq(PlotLogic.Source(bp("Wall"), 0, true, true), "fee", "unlocked only means something for an unlock")
	end)

	t.test("VisitSpot: the spawn pad first, then spots around it, always inside the plot", function()
		t.eq({ PlotLogic.VisitSpot(120, function()
			return false
		end) }, { 0, -18 })
		local tried = 0
		local x, z = PlotLogic.VisitSpot(120, function()
			tried += 1
			return tried < 3
		end)
		t.eq({ x, z }, { -8, -18 }, "the third spot is the first good one")
		for _, size in ipairs({ 120, 140, 200 }) do
			for _, spot in ipairs(PlotLogic.VisitCandidates(size)) do
				t.ok(math.abs(spot[1]) <= size / 2 - PlotLogic.VisitMargin, "x inside at " .. size)
				t.ok(math.abs(spot[2]) <= size / 2 - PlotLogic.VisitMargin, "z inside at " .. size)
			end
		end
		t.eq(
			{ PlotLogic.VisitSpot(120, function()
				return true
			end) },
			{ 0, -18 },
			"everything bad: the pad itself"
		)
	end)

	t.test("homesteads don't all look alike", function()
		local seen: { [string]: boolean } = {}
		for i = 1, #PlotData.Homes do
			local look = PlotData.Look(i)
			seen[look.name] = true
			t.ok(#look.top == 3 and #look.edge == 3 and #look.rail == 3, look.name .. " is complete")
			-- The ground round a plot is grass for every home; what differs is the
			-- dark grey platform's tone and the rail (PlotPlatform.spec checks them).
			t.ok(look.top[1] < 120 and look.top[2] < 120 and look.top[3] < 120, look.name .. " is a dark grey platform")
		end
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		t.ok(n >= 5, "at least five different looks across the homes")
		t.ok(PlotData.Look(1).name ~= PlotData.Look(2).name, "neighbours differ")
	end)

	t.test("a placed mill or chop saw blocks what is placed on it, and what it is placed on", function()
		local SawmillLogic = t.shared("SawmillLogic")
		local ChopSawLogic = t.shared("ChopSawLogic")
		local mill = SawmillLogic.Blueprint("SawmillRickety")
		local floor = PlotData.Blueprint("Floor")
		t.ok((PlotLogic.Check(mill, 0, 0, 0, 1, {})), "an empty yard takes it")
		local placed = { { uid = "m", blueprintId = "SawmillRickety", x = 0, z = 0, rot = 0 } }
		local okFloor, why = PlotLogic.Check(floor, 0, 0, 0, 1, placed)
		t.eq(okFloor, false)
		t.eq(why, "Something's in the way")
		local okMill = PlotLogic.Check(mill, 2, 0, 0, 1, placed)
		t.eq(okMill, false, "a second mill can't sit inside the first")
		t.ok((PlotLogic.Check(floor, 0, 30, 0, 1, placed)), "clear ground is fine")
		local saw = ChopSawLogic.Blueprint(ChopSawLogic.MachineId or "ChopSaw")
		if saw then
			t.eq(
				(PlotLogic.Check(floor, 0, 0, 0, 1, { { uid = "c", blueprintId = saw.id, x = 0, z = 0, rot = 0 } })),
				false
			)
		end
	end)

	t.test("a bought square is part of the plot for Check, with its squares passed in", function()
		local floor = PlotData.Blueprint("Floor")
		-- Tier 1 is 80 wide (half 40); the square at (1,0) spans x 20..60.
		t.eq((PlotLogic.Check(floor, 52, 0, 0, 1, {})), false, "outside without the square")
		t.eq((PlotLogic.Check(floor, 52, 0, 0, 1, {}, nil, 0, { "1,0" })), true, "inside with it")
	end)
end
