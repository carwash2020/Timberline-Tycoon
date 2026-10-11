--!nocheck
-- Lane R: Red Mesa's numbers, and that they sit on what Builder reserved.
return function(t)
	local MesaData = t.load("ReplicatedStorage/Shared/Regions/MesaData")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BiomeData = t.shared("BiomeData")

	local function dist(ax, az, bx, bz)
		return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
	end

	t.test("the centre, radius and stage mirror WorldLayout and BiomeData", function()
		local region = WorldLayout.RedMesa
		t.eq({ MesaData.Centre.x, MesaData.Centre.z, MesaData.Radius }, { region.x, region.z, region.radius })
		t.eq(MesaData.NeedsStage, 4)
		t.eq(BiomeData.Get("mesa").needsStage, MesaData.NeedsStage)
		local d = BiomeData.RegionDiscs.mesa
		t.eq({ d.x, d.z, d.radius }, { region.x, region.z, region.radius })
	end)

	t.test("the truck lot, junction and rare spot are Builder's anchors", function()
		local lot = WorldPlan.MesaTruckLot
		t.eq(
			{ MesaData.TruckLot.x, MesaData.TruckLot.z, MesaData.TruckLot.sx, MesaData.TruckLot.sz },
			{ lot.x, lot.z, lot.sx, lot.sz }
		)
		local spawn = nil
		for _, s in ipairs(WorldPlan.UniqueItemSpawns) do
			if s.id == "redmesa" then
				spawn = s
			end
		end
		t.eq({ MesaData.UniqueSpot.x, MesaData.UniqueSpot.z }, { spawn.x, spawn.z })
		local j = nil
		for _, junction in ipairs(WorldLayout.Junctions) do
			if junction.name == "Mesa" then
				j = junction
			end
		end
		t.eq({ MesaData.Junction.x, MesaData.Junction.z, MesaData.Junction.radius }, { j.at.X, j.at.Y, j.radius })
	end)

	t.test("eight SlabNodes: WorldPlan's are MesaData's, on the rim, and clear of MesaRoad and its junction", function()
		t.eq(#WorldPlan.SlabNodes, 8)
		local road = nil
		for _, r in ipairs(WorldLayout.Roads) do
			if r.name == "MesaRoad" then
				road = r
			end
		end
		local c = MesaData.Centre
		for i, node in ipairs(MesaData.QuarryNodes()) do
			local theirs = WorldPlan.SlabNodes[i]
			t.eq({ theirs.id, theirs.x, theirs.z }, { node.id, node.x, node.z })
			t.ok(node.z > c.z, node.id .. " is on the +Z (north) face")
			-- 8 studs in from the edge.
			t.ok(math.abs(dist(node.x, node.z, c.x, c.z) - (MesaData.Radius - 8)) < 1e-6, node.id .. " is off the rim")
			local dj = dist(node.x, node.z, MesaData.Junction.x, MesaData.Junction.z)
			t.ok(dj > MesaData.Junction.radius + 12, string.format("%s is %.0f from the junction circle", node.id, dj))
			local dr = WorldLayout.PolylineDistance(t.roblox.Vector2.new(node.x, node.z), road.points)
			t.ok(dr > road.width / 2 + 12, string.format("%s is %.0f off MesaRoad", node.id, dr))
			-- Close enough to carry a slab to the lot: under 90 studs.
			t.ok(
				dist(node.x, node.z, MesaData.TruckLot.x, MesaData.TruckLot.z) < 100,
				node.id .. " is far from the lot"
			)
		end
	end)

	t.test("the RED MESA signpost stands clear of every quarry wall", function()
		local sign = nil
		for _, s in ipairs(WorldPlan.RoadSigns(WorldPlan.BiomeSignText)) do
			if string.match(s.text, "^[^\n]+") == "RED MESA" then
				sign = s
			end
		end
		t.ok(sign ~= nil, "the signpost")
		local p = sign.cframe.Position
		for _, node in ipairs(MesaData.QuarryNodes()) do
			-- A wall is 15 wide and the signpost 11, so 28 studs keeps them apart.
			t.ok(
				dist(node.x, node.z, p.X, p.Z) >= 28,
				node.id .. " is " .. dist(node.x, node.z, p.X, p.Z) .. " from the sign"
			)
		end
	end)

	t.test("the butte is three 15-stud steps, Sandstone then Sand then Rock, inside the disc", function()
		local steps = MesaData.Butte.steps
		t.eq(#steps, 3)
		t.eq({ steps[1].height, steps[2].height, steps[3].height }, { 15, 30, 45 })
		t.eq({ steps[1].color, steps[2].color, steps[3].color }, { "sandstone", "sand", "rock" })
		local b = MesaData.Butte
		t.ok(
			dist(b.x, b.z, MesaData.Centre.x, MesaData.Centre.z) + steps[1].radius <= MesaData.Radius,
			"the butte leaves the disc"
		)
		t.ok(steps[1].radius > steps[2].radius and steps[2].radius > steps[3].radius, "each step is narrower")
		t.eq({ b.x, b.z }, { MesaData.UniqueSpot.x, MesaData.UniqueSpot.z }, "the rare find is on the top")
		-- Clear of the truck lot.
		local lot = MesaData.TruckLot
		local nx = math.clamp(b.x, lot.x - lot.sx / 2, lot.x + lot.sx / 2)
		local nz = math.clamp(b.z, lot.z - lot.sz / 2, lot.z + lot.sz / 2)
		t.ok(dist(b.x, b.z, nx, nz) > steps[1].radius + 4, "the butte touches the truck lot")
	end)

	t.test("the overlook ramp is 6 wide and at most 12 degrees, and the deck is inside the disc", function()
		local o = MesaData.Overlook
		t.eq(o.rampWidth, 6)
		t.ok(o.rampDegrees <= 12)
		local run = o.deckRise / math.tan(math.rad(o.rampDegrees))
		t.ok(
			dist(o.x, o.z + o.deckSize / 2 + run, MesaData.Centre.x, MesaData.Centre.z) <= MesaData.Radius,
			"the ramp's foot leaves the disc"
		)
		local b = MesaData.Butte
		t.ok(dist(o.x, o.z, b.x, b.z) > b.steps[1].radius + o.deckSize / 2, "the deck stands in the butte")
		local lot = MesaData.TruckLot
		t.ok(
			o.z + o.deckSize / 2 + run < lot.z - lot.sz / 2 or math.abs(o.x - lot.x) > lot.sx / 2 + 4,
			"the ramp crosses the truck lot"
		)
	end)

	t.test("the quarry refills in 60 seconds and has a reach", function()
		t.eq(MesaData.Quarry.respawnSec, 60)
		t.ok(MesaData.Quarry.reach >= 8)
	end)

	t.test("budgets: at most 40 ironwood, 2 lights, a 60-part arch, a 30-part overlook", function()
		local b = MesaData.Budgets
		t.ok(b.trees <= 40 and b.lights <= 2 and b.landmark <= 60 and b.overlook <= 30 and b.scatterPiece <= 10)
		t.ok(BiomeData.Get("mesa").trees.ironwood <= b.trees)
		t.eq(MesaData.LanternCount, 2)
	end)

	t.test("together with Gloam Hollow the mesa keeps at most 70 trees (it is under 700 apart)", function()
		local mesa = BiomeData.Get("mesa").trees.ironwood
		local gloam = BiomeData.Get("grove").trees.phantomwood
		local d =
			dist(MesaData.Centre.x, MesaData.Centre.z, BiomeData.Get("grove").area.x, BiomeData.Get("grove").area.z)
		t.ok(d >= 500, "regions are at least 500 apart")
		if d < 700 then
			t.ok(mesa + gloam <= 70, mesa + gloam .. " trees")
		end
	end)

	t.test(
		"no ironwood stands in the quarry, butte, overlook, arch or truck lot, and the count is the biome's",
		function()
			local n = 0
			for _, spot in ipairs(WorldPlan.RegionTrees()) do
				if spot.biome == "mesa" then
					n += 1
					t.eq(spot.woodId, "ironwood")
					t.ok(not MesaData.Blocked(spot.position.X, spot.position.Z, 0), "an ironwood in the build")
				end
			end
			t.ok(n >= 25 and n <= MesaData.Budgets.trees, n .. " ironwood")
		end
	)
end
