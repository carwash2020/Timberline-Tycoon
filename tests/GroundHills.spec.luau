--!nocheck
-- T397: the parking lot fits its bays, the ground has gentle hills, and the
-- roads, plots, store pads and the lot stay level. Samples are every 6 studs;
-- a slope is the steepest rise over 4 studs to any of the four neighbours.
return function(t)
	local roblox = t.roblox
	local Vector2 = roblox.Vector2
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TruckLayout = t.shared("TruckLayout")
	local VehicleLogic = t.shared("VehicleLogic")
	local ItemCatalog = t.shared("ItemCatalog")
	local PlotData = t.shared("PlotData")
	local BiomeData = t.shared("BiomeData")
	local UndergroundData = t.load("ReplicatedStorage/Shared/World/UndergroundData")

	local HeightAt = TerrainGen.HeightAt
	local function slopeDeg(x, z)
		local h = HeightAt(x, z)
		local m = math.max(
			math.abs(HeightAt(x + 4, z) - h),
			math.abs(HeightAt(x - 4, z) - h),
			math.abs(HeightAt(x, z + 4) - h),
			math.abs(HeightAt(x, z - 4) - h)
		) / 4
		return math.deg(math.atan(m))
	end

	---------------------------------------------------------------------------
	-- 1. The lot and its stalls
	---------------------------------------------------------------------------

	-- The largest truck from the vehicle data (its footprint from above, in
	-- studs: TruckLayout.RigSize, the same numbers VehicleService parks by).
	local function largestTruck()
		local best
		for id, truck in pairs(ItemCatalog.Trucks) do
			local length, width = TruckLayout.RigSize(TruckLayout.For(truck))
			if not best or length > best.length then
				best = { name = id, length = length, width = width }
			end
		end
		return best
	end

	t.test(
		"the stalls the largest truck uses are its footprint plus 1.5 wide and 3 long, and at most twice it",
		function()
			local truck = largestTruck()
			t.eq(truck.name, "LoggingRig")
			local town = WorldPlan.Town()
			local usable = 0
			for i, size in ipairs(town.parkingSizes) do
				-- Every stall long enough to hold it (the shorter ones are for the small trucks).
				if size.Z >= truck.length then
					usable += 1
					t.ok(
						size.X >= truck.width + 1.5,
						string.format("stall %d: %.2f wide for a %.2f wide %s", i, size.X, truck.width, truck.name)
					)
					t.ok(
						size.Z >= truck.length + 3,
						string.format("stall %d: %.2f long for a %.2f long %s", i, size.Z, truck.length, truck.name)
					)
					t.ok(
						size.X <= 2 * truck.width,
						string.format("stall %d is over twice as wide as the %s", i, truck.name)
					)
					t.ok(
						size.Z <= 2 * truck.length,
						string.format("stall %d is over twice as long as the %s", i, truck.name)
					)
				end
			end
			t.ok(usable >= 3, "the largest truck has stalls: " .. usable)
			-- The door's width to spare: 16 wide against a 12.61 wide truck.
			t.ok(WorldPlan.ParkingBays.long.X - truck.width >= 1.5, "room to open a door")
		end
	)

	t.test("the lot ends at its last stall (T397: x1 146 -> 138)", function()
		local lot = WorldLayout.ParkingLot
		local town = WorldPlan.Town()
		local east = -math.huge
		for i, cf in ipairs(town.parkingSlots) do
			east = math.max(east, cf.X + town.parkingSizes[i].X / 2)
		end
		t.ok(lot.x1 >= east + 1, "every stall and its lane are on the lot")
		t.ok(
			lot.x1 <= east + 2,
			string.format("no empty slab past the stalls: lot ends %.1f, last stall %.1f", lot.x1, east)
		)
	end)

	---------------------------------------------------------------------------
	-- 2. Roads, plots, store pads, the sale area and the lot
	---------------------------------------------------------------------------

	-- Where a road polyline has a vertex, or another road is within a lane: the
	-- ground is a junction, and crosses the other road's own grade.
	local function nearJunction(road, x, z)
		local p = Vector2.new(x, z)
		for _, q in ipairs(road.points) do
			if (p - q).Magnitude < road.width then
				return true
			end
		end
		for _, other in ipairs(WorldLayout.Roads) do
			if other ~= road then
				local d = math.huge
				for i = 1, #other.points - 1 do
					d = math.min(d, (WorldLayout.SegmentDistance(p, other.points[i], other.points[i + 1])))
				end
				if d < other.width / 2 + road.width / 2 + 4 then
					return true
				end
			end
		end
		return false
	end

	t.test(
		"roads: on the surface along every centreline, at most 5 degrees along (the ravine road 10.3), level across",
		function()
			local maxAlong, maxAcross = 0, 0
			local samples = 0
			for _, road in ipairs(WorldLayout.Roads) do
				local pts = road.points
				for i = 1, #pts - 1 do
					local a, b = pts[i], pts[i + 1]
					local len = (b - a).Magnitude
					local dir = (b - a) / math.max(len, 1e-6)
					local side = Vector2.new(-dir.Y, dir.X)
					local prev = nil
					for s = 0, len, 4 do
						local p = a + dir * s
						local h = HeightAt(p.X, p.Y)
						local surface = TerrainGen.RoadHeightAt(p.X, p.Y)
						t.ok(surface ~= nil, string.format("%s at (%.0f, %.0f) is a road", road.name, p.X, p.Y))
						if surface then
							samples += 1
							t.ok(
								math.abs(h - surface) <= 0.2,
								string.format(
									"%s at (%.0f, %.0f): ground %.2f, road %.2f",
									road.name,
									p.X,
									p.Y,
									h,
									surface
								)
							)
						end
						if prev then
							local deg = math.deg(math.atan(math.abs(h - prev) / 4))
							maxAlong = math.max(maxAlong, deg)
							-- The ravine road is the one exception: 54 studs down into the
							-- Gloam ravine in 316 (10.2 degrees, as it always was).
							t.ok(
								deg <= (if road.name == "RavineRoad" then 10.3 else 5.0001),
								string.format("%s at (%.0f, %.0f) climbs %.2f degrees", road.name, p.X, p.Y, deg)
							)
						end
						prev = h
						-- Level across: on straights it is level to a fifth of a stud.
						-- At a bend or a crossing the other road's grade shows across
						-- this one, never more than a 5 degree cross-fall.
						local junction = nearJunction(road, p.X, p.Y)
						for _, f in ipairs({ -0.4, 0.4 }) do
							local q = p + side * (road.width * f)
							local across = math.abs(HeightAt(q.X, q.Y) - h)
							maxAcross = math.max(maxAcross, if junction then 0 else across)
							local allow = if junction
								then road.width * 0.4 * math.tan(
									math.rad(if road.name == "RavineRoad" then 10.3 else 5)
								) + 0.1
								else 0.2
							t.ok(
								across <= allow,
								string.format(
									"%s at (%.0f, %.0f) is %.2f off level across",
									road.name,
									p.X,
									p.Y,
									across
								)
							)
						end
					end
				end
			end
			t.ok(samples > 1500, "sampled the roads: " .. samples)
			print(
				string.format(
					"[GroundHills] roads: %d samples, steepest %.2f degrees along, %.2f studs across a straight",
					samples,
					maxAlong,
					maxAcross
				)
			)
		end
	)

	local function rectSamples(r, step)
		local out = {}
		local x = r.x0
		while x <= r.x1 + 1e-6 do
			local z = r.z0
			while z <= r.z1 + 1e-6 do
				table.insert(out, { x, z })
				z += step
			end
			x += step
		end
		return out
	end

	t.test("plots: HeightAt is 0 on every pad, flat", function()
		local half = PlotData.Pad / 2
		for i, slot in ipairs(PlotData.Slots) do
			local rect = { x0 = slot.X - half, x1 = slot.X + half, z0 = slot.Y - half, z1 = slot.Y + half }
			-- Roads and water may cross a pad's edge; its inside is the shelf.
			for _, p in ipairs(rectSamples(rect, 8)) do
				local wet = TerrainGen.WaterLevelAt(p[1], p[2]) ~= nil
				-- (Plot 3's north-east corner is under the mine's hill, the rock over its
				-- decline, up to +7: not this job's ground, flagged in the PR.)
				if
					not wet
					and TerrainGen.RoadHeightAt(p[1], p[2]) == nil
					and UndergroundData.HillAt(p[1], p[2]) == 0
				then
					t.ok(
						math.abs(HeightAt(p[1], p[2])) <= 0.2,
						string.format("plot %d at (%.0f, %.0f) is %.2f", i, p[1], p[2], HeightAt(p[1], p[2]))
					)
				end
			end
		end
	end)

	t.test("store pads, the sale area and the lot: height 0 and no slope, with an 8-stud apron", function()
		local rects = {}
		for _, zone in ipairs(WorldLayout.StorePads) do
			table.insert(rects, zone)
		end
		for _, floor in ipairs(WorldLayout.TownFloors) do
			table.insert(rects, floor)
		end
		-- The sell pad and its zone (the station's floor holds them) and the lot.
		table.insert(rects, { x0 = 39, x1 = 67, z0 = 95, z1 = 127 })
		table.insert(rects, WorldLayout.ParkingLot)
		t.ok(#rects >= 15, "pads: " .. #rects)
		for _, r in ipairs(rects) do
			-- On the pad: height 0 and no slope.
			for _, p in ipairs(rectSamples(r, 4)) do
				t.ok(
					math.abs(HeightAt(p[1], p[2])) <= 0.01,
					string.format(
						"pad (%s) at (%.0f, %.0f) is %.2f high",
						tostring(r.name),
						p[1],
						p[2],
						HeightAt(p[1], p[2])
					)
				)
			end
			-- Its slope is 0 (measured from 4 studs in, so the apron is not read).
			local inner = { x0 = r.x0 + 4, x1 = r.x1 - 4, z0 = r.z0 + 4, z1 = r.z1 - 4 }
			if inner.x0 <= inner.x1 and inner.z0 <= inner.z1 then
				for _, p in ipairs(rectSamples(inner, 4)) do
					t.ok(
						slopeDeg(p[1], p[2]) < 0.5,
						string.format("pad (%s) at (%.0f, %.0f) is sloped", tostring(r.name), p[1], p[2])
					)
				end
			end
			-- The 8-stud apron round it eases to the country without a wall.
			local apron = { x0 = r.x0 - 8, x1 = r.x1 + 8, z0 = r.z0 - 8, z1 = r.z1 + 8 }
			for _, p in ipairs(rectSamples(apron, 4)) do
				t.ok(
					slopeDeg(p[1], p[2]) <= 15,
					string.format(
						"apron of (%s) at (%.0f, %.0f) is %.1f degrees",
						tostring(r.name),
						p[1],
						p[2],
						slopeDeg(p[1], p[2])
					)
				)
			end
		end
	end)

	---------------------------------------------------------------------------
	-- 3. Hills
	---------------------------------------------------------------------------

	t.test("the hill layer is nothing within 8 studs of a road, plot or pad edge", function()
		t.eq(TerrainGen.HillClear, 8)
		local seen, shown = 0, 0
		-- Around every road, plot shelf and store pad: rings 0 to 8 studs out.
		local function check(x, z, what)
			local rc = TerrainGen.RoadClearance(x, z)
			local pc = WorldLayout.PadClearance(x, z, 100)
			if math.min(rc, pc) <= 8 then
				seen += 1
				t.eq(TerrainGen.HillLiftAt(x, z), 0, string.format("%s: hills at (%.0f, %.0f)", what, x, z))
			else
				shown += 1
			end
		end
		for _, road in ipairs(WorldLayout.Roads) do
			local pts = road.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local len = (b - a).Magnitude
				local dir = (b - a) / math.max(len, 1e-6)
				local side = Vector2.new(-dir.Y, dir.X)
				for s = 0, len, 12 do
					local p = a + dir * s
					for off = -(road.width / 2 + 10), road.width / 2 + 10, 3 do
						local q = p + side * off
						check(q.X, q.Y, road.name)
					end
				end
			end
		end
		for _, slot in ipairs(PlotData.Slots) do
			local half = PlotData.Pad / 2
			for d = -20, 20, 2 do
				check(slot.X + half + d, slot.Y, "plot east edge")
				check(slot.X - half + d, slot.Y + 30, "plot west edge")
				check(slot.X + 20, slot.Y + half + d, "plot north edge")
				check(slot.X - 20, slot.Y - half + d, "plot south edge")
			end
		end
		for _, zone in ipairs(WorldLayout.StorePads) do
			for d = -6, 14, 2 do
				check(zone.x1 + d, (zone.z0 + zone.z1) / 2, "store pad east edge")
				check(zone.x0 - d, (zone.z0 + zone.z1) / 2, "store pad west edge")
			end
		end
		t.ok(seen > 800, "samples inside the 8 studs: " .. seen)
		t.ok(shown > 100, "samples past them: " .. shown)
	end)

	t.test(
		"the hills are real: up to +18 in the Hills, a 9 stud meadow, and they come back past the 8 studs",
		function()
			t.eq(TerrainGen.HillsAmp, 18)
			t.eq(TerrainGen.MeadowSwellAmp + TerrainGen.MeadowFineAmp, TerrainGen.MeadowAmp)
			t.ok(
				TerrainGen.MeadowAmp >= 9 and TerrainGen.MeadowAmp <= 9.2,
				"the meadow is 9 studs (9.2 at the noise's very most)"
			)
			local area = BiomeData.Get("hills").area
			local hiHills, hiMeadow = 0, 0
			for x = area.x - area.radius, area.x + area.radius, 5 do
				for z = area.z - area.radius, area.z + area.radius, 5 do
					if (x - area.x) ^ 2 + (z - area.z) ^ 2 < area.radius ^ 2 then
						hiHills = math.max(hiHills, TerrainGen.HillLiftAt(x, z))
					end
				end
			end
			-- The open meadow east of town, clear of every biome and road.
			for x = 700, 800, 10 do
				for z = -400, -300, 10 do
					hiMeadow = math.max(hiMeadow, math.abs(TerrainGen.HillLiftAt(x, z)))
				end
			end
			local fine = TerrainGen.MeadowFineAmp
			-- Domes are at most 18 plus the meadow's own fine rolling.
			t.ok(hiHills <= 18 + fine + 1e-6, "the Hills' lift is at most 18 + the meadow's fine rolling: " .. hiHills)
			-- Was +5.85 with the 200 stud ramp; the road-grade ramp reaches +9.4, about what
			-- the 15 degree rule allows between the roads that cut the Hills into cells.
			t.ok(hiHills >= 9, "the Hills rise to at least +9: " .. hiHills)
			t.ok(hiMeadow <= fine + 1e-6, "the meadow's fine rolling is at most " .. fine .. ": " .. hiMeadow)
		end
	)

	-- Ground the 15 degree rule does not describe: cliffs, mountains, caves,
	-- the cone, water, the coast and what is built into them on purpose.
	local CONE = WorldLayout.VolcanoCone
	local function builtSteep(x, z)
		-- The mountains framing the map (WorldLayout.Mountains.start and out).
		local ms = WorldLayout.Mountains.start
		if x < -ms + 8 or z > ms - 8 or z < -ms + 8 or (z > WorldLayout.Coast.northZ + 150 - 8 and x > ms - 8) then
			return true
		end
		local dx, dz = x - CONE.x, z - CONE.z
		if dx * dx + dz * dz < (CONE.radius + 40) ^ 2 then
			return true
		end
		for _, rim in ipairs(WorldLayout.Rims) do
			local d = math.sqrt((x - rim.cx) ^ 2 + (z - rim.cz) ^ 2)
			if d > rim.inner - 30 and d < rim.outer + 30 then
				return true
			end
		end
		local g = BiomeData.Get("grove").area
		if (x - g.x) ^ 2 + (z - g.z) ^ 2 < (WorldLayout.GroveRidge.outer + 40) ^ 2 then
			return true
		end
		for _, o in ipairs({ { 0, 0 }, { 12, 0 }, { -12, 0 }, { 0, 12 }, { 0, -12 } }) do
			if TerrainGen.WaterLevelAt(x + o[1], z + o[2]) then
				return true
			end
		end
		for _, c in ipairs(UndergroundData.Caves) do
			if math.abs(x - c.x) < c.sx / 2 + 40 and math.abs(z - c.z) < c.sz / 2 + 40 then
				return true
			end
		end
		if x > 80 and x < 280 and z > -280 and z < -90 then
			return true -- the mine's hill
		end
		for i = 1, #WorldLayout.TunnelPoints - 1 do
			local a, b = WorldLayout.TunnelPoints[i], WorldLayout.TunnelPoints[i + 1]
			if WorldLayout.SegmentDistance(Vector2.new(x, z), a, b) < 330 then
				return true
			end
		end
		-- The Gloam ravine and the road that grades down into it (cut to -48).
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "RavineRoad" then
				for i = 1, #road.points - 1 do
					if WorldLayout.SegmentDistance(Vector2.new(x, z), road.points[i], road.points[i + 1]) < 80 then
						return true
					end
				end
			end
		end
		local coast = WorldLayout.Coast
		if z < coast.northZ + 40 and x > coast.shoreX - 250 then
			return true
		end
		local isl = WorldLayout.Island
		if (x - isl.x) ^ 2 + (z - isl.z) ^ 2 < (isl.radius + 100) ^ 2 then
			return true
		end
		for _, region in ipairs(WorldLayout.ReservedRegions) do
			if (x - region.x) ^ 2 + (z - region.z) ^ 2 < (region.radius + 60) ^ 2 then
				return true
			end
		end
		return false
	end

	t.test("forest ground is at most 15 degrees, away from the banks of a road crossing", function()
		local total, worst, worstAt = 0, 0, nil
		local bad, nBad = {}, 0
		for x = -980, 980, 12 do
			for z = -980, 980, 12 do
				if not builtSteep(x, z) and TerrainGen.RoadClearance(x, z) > 12 then
					total += 1
					local deg = slopeDeg(x, z)
					if deg > worst then
						worst, worstAt = deg, string.format("(%d, %d)", x, z)
					end
					if deg > 15 then
						nBad += 1
						if #bad < 12 then
							table.insert(bad, string.format("(%d, %d) is %.1f degrees", x, z, deg))
						end
					end
				end
			end
		end
		t.ok(total > 8000, "forest samples: " .. total)
		print(
			string.format(
				"[GroundHills] forest ground: %d samples, %d over 15, steepest %.1f degrees at %s",
				total,
				nBad,
				worst,
				tostring(worstAt)
			)
		)
		t.eq(bad, {}, "forest ground over 15 degrees")
	end)

	t.test("the Hills' cells at a finer scan (every 6 studs): at most 15 degrees too", function()
		local worst, worstAt, total = 0, nil, 0
		for x = -740, -230, 6 do
			for z = -150, 440, 6 do
				if not builtSteep(x, z) and TerrainGen.RoadClearance(x, z) > 12 then
					total += 1
					local deg = slopeDeg(x, z)
					if deg > worst then
						worst, worstAt = deg, string.format("(%d, %d)", x, z)
					end
				end
			end
		end
		t.ok(total > 4000, "Hills samples: " .. total)
		print(
			string.format(
				"[GroundHills] Hills cells: %d samples, steepest %.2f degrees at %s",
				total,
				worst,
				tostring(worstAt)
			)
		)
		t.ok(worst <= 15, string.format("the Hills are %.2f degrees at %s", worst, tostring(worstAt)))
	end)
end
