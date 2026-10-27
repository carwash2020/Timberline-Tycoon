--!nocheck
-- T409 ground §5. Written before the landform change: on main a276c1b these
-- fail (WorldHalf 1000, lodge at the old snow-road pin, draft roads ungraded,
-- hard region cuts, corridor still an annotation). Cloud tests do not run
-- physics; this samples HeightAt and SurfaceMaterial only.

return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local Draft = t.load("ReplicatedStorage/Shared/World/WorldPlanDraft")
	local GameConfig = t.load("ReplicatedStorage/Shared/GameConfig")

	local GRASS = { Grass = true, LeafyGrass = true }
	local STEEP = math.tan(math.rad(40))
	local GRADE = 0.12

	local function onPad(x, z)
		local ok, Valley = pcall(function()
			return t.load("ReplicatedStorage/Shared/World/ValleyGround")
		end)
		if ok and Valley and Valley.OnPad and Valley.OnPad(x, z) then
			return true
		end
		return WorldLayout.FlatWeight(x, z) > 0.5
	end

	t.test("WorldHalf holds the Frostpeak rim and Lantern Isle", function()
		t.eq(WorldLayout.WorldHalf, 1350)
		local frost = Draft.GetRegion("frost")
		local isle = Draft.GetRegion("isle")
		t.ok(frost.z + frost.radius <= WorldLayout.WorldHalf, "frost rim inside the square")
		t.ok(math.abs(isle.x) + isle.radius <= WorldLayout.WorldHalf, "isle inside the square")
		t.eq(frost.pastLive, nil)
		t.eq(isle.pastLive, nil)
		-- Past the square the sampler still returns a number (no crash).
		t.eq(type(TerrainGen.HeightAt(1400, 1400)), "number")
		t.eq(type(TerrainGen.HeightAt(-340, 1200)), "number")
		t.eq(type(TerrainGen.SurfaceMaterial(1400, -800, 0, 0)), "string")
	end)

	t.test("draft roads climb at most 12 percent along the centreline", function()
		for _, road in ipairs(Draft.Roads) do
			local pts = road.points
			local prev = pts[1]
			local ph = TerrainGen.HeightAt(prev.x, prev.z)
			for i = 2, #pts do
				local b = pts[i]
				local dx, dz = b.x - prev.x, b.z - prev.z
				local len = math.sqrt(dx * dx + dz * dz)
				local steps = math.max(1, math.floor(len / 8))
				for s = 1, steps do
					local u = s / steps
					local x, z = prev.x + dx * u, prev.z + dz * u
					local h = TerrainGen.HeightAt(x, z)
					local run = len / steps
					local grade = math.abs(h - ph) / math.max(run, 1e-3)
					t.ok(
						grade <= GRADE + 0.002,
						string.format("%s grade %.1f%% near (%.0f, %.0f)", road.name, grade * 100, x, z)
					)
					ph = h
				end
				prev = b
			end
		end
	end)

	t.test("ground steeper than 40 degrees is never grass", function()
		local function check(x, z)
			local slope = TerrainGen.SlopeAt(x, z)
			if slope > STEEP then
				local h = TerrainGen.HeightAt(x, z)
				local m = TerrainGen.SurfaceMaterial(x, z, h, slope)
				t.ok(not GRASS[m], string.format("%s at %.0f deg (%.0f, %.0f)", m, math.deg(math.atan(slope)), x, z))
			end
		end
		for x = -1200, 1200, 48 do
			for z = -1200, 1200, 48 do
				check(x, z)
			end
		end
		local caldera = Draft.GetRegion("caldera")
		for d = 12, 48, 4 do
			check(caldera.x + d, caldera.z)
			check(caldera.x, caldera.z + d)
		end
	end)

	t.test("a region belt blends for at least 30 studs and the bed stays gravel", function()
		t.eq(Draft.Corridor.beltTrunk, 48)
		t.eq(Draft.Corridor.beltFoot, 32)
		t.eq(Draft.Corridor.gateClear, 30)
		local checked = 0
		for _, belt in ipairs(Draft.Belts) do
			if belt.depthStuds < 30 then
				t.ok(false, belt.id .. " depth " .. tostring(belt.depthStuds))
			end
			local ox, oz = belt.outer.x, belt.outer.z
			local ex, ez = belt.edge.x, belt.edge.z
			local dx, dz = ex - ox, ez - oz
			local len = math.sqrt(dx * dx + dz * dz)
			if len < 8 then
				continue
			end
			local nx, nz = -dz / len, dx / len
			local off = belt.width / 2 + 6
			local first, lastChange, lastMat = nil, nil, nil
			local steps = math.floor(len / 2)
			for i = 0, steps do
				local u = i / steps
				local x = ox + dx * u + nx * off
				local z = oz + dz * u + nz * off
				local h = TerrainGen.HeightAt(x, z)
				local m = TerrainGen.SurfaceMaterial(x, z, h, TerrainGen.SlopeAt(x, z))
				if first == nil then
					first = m
				end
				if m ~= first then
					lastChange = u * len
				end
				lastMat = m
			end
			local span = if first ~= lastMat and lastChange then lastChange else 0
			t.ok(
				span >= 30,
				string.format("%s blend span %.1f (from %s to %s)", belt.id, span, tostring(first), tostring(lastMat))
			)
			if WorldLayout.FlatWeight(ox, oz) < 0.5 then
				local mx, mz = (ox + ex) / 2, (oz + ez) / 2
				local hm = TerrainGen.HeightAt(mx, mz)
				local bed = TerrainGen.SurfaceMaterial(mx, mz, hm, 0)
				t.eq(bed, "Asphalt", belt.id .. " bed")
			end
			checked += 1
		end
		t.ok(checked >= 4, "belts walked " .. checked)
	end)

	t.test("no flat sheet larger than 64 studs outside a declared pad", function()
		local step = 32
		local eps = 0.08
		local function h(x, z)
			return TerrainGen.HeightAt(x, z)
		end
		for x = -1280, 1280, step do
			for z = -1280, 1280, step do
				local h0 = h(x, z)
				local flat = true
				for _, o in ipairs({
					{ 0, 0 },
					{ step, 0 },
					{ step * 2, 0 },
					{ 0, step },
					{ step, step },
					{ step * 2, step },
					{ 0, step * 2 },
					{ step, step * 2 },
					{ step * 2, step * 2 },
				}) do
					if math.abs(h(x + o[1], z + o[2]) - h0) > eps then
						flat = false
						break
					end
				end
				if flat then
					local cx, cz = x + step, z + step
					local surface = TerrainGen.WaterLevelAt(cx, cz)
					-- A bed under the river or the sea is not a sheet a player drives.
					if surface ~= nil and h0 < surface - 0.05 then
						continue
					end
					t.ok(onPad(cx, cz), string.format("flat 64 sheet at (%.0f, %.0f) height %.2f", cx, cz, h0))
				end
			end
		end
	end)

	t.test("a declared pad has a bank or kerb, not an endless baseplate", function()
		local function edge(x, z, ox, oz, name)
			if onPad(x, z) and onPad(x + ox, z + oz) then
				return
			end
			local a = TerrainGen.HeightAt(x, z)
			local b = TerrainGen.HeightAt(x + ox, z + oz)
			local slope = TerrainGen.SlopeAt(x + ox * 0.5, z + oz * 0.5)
			local hb = TerrainGen.HeightAt(x + ox, z + oz)
			local mat = TerrainGen.SurfaceMaterial(x + ox, z + oz, hb, slope)
			local kerb = mat == "Rock" or mat == "Slate" or mat == "Ground" or mat == "Asphalt"
			t.ok(
				math.abs(a - b) >= 0.25 or slope > 0.08 or kerb,
				string.format("%s edge (%.0f, %.0f) has no bank", name, x, z)
			)
		end
		for _, zone in ipairs(WorldLayout.FlatZones) do
			if zone.name == "Town" or zone.name == "Plot" then
				local mx = (zone.x0 + zone.x1) / 2
				local mz = (zone.z0 + zone.z1) / 2
				edge(mx, zone.z0 + 2, 0, -18, zone.name)
				edge(zone.x1 - 2, mz, 18, 0, zone.name)
			end
		end
	end)

	t.test("the gate lodge faces north on HeightAt and the corridor is live", function()
		t.eq(Draft.Built, true)
		t.eq(Draft.Corridor.built, true)
		local cf = WorldPlan.GateLodge()
		t.ok(cf, "lodge")
		local p = cf.Position
		t.ok(math.abs(p.X + 40) <= 1 and math.abs(p.Z - 720) <= 1, string.format("(%.1f, %.1f)", p.X, p.Z))
		t.ok(cf.LookVector.Z > 0.7, "facing north")
		t.ok(math.abs(p.Y - TerrainGen.HeightAt(p.X, p.Z)) < 0.05, "Y")
		local frost = Draft.GetRegion("frost")
		local sky = Draft.GetRegion("skyroot")
		t.ok(Draft.DiscGap(frost, sky) >= 10, "disc gap")
		-- The gap is still a gap after the height noise: the two centres are
		-- not the same height family smashed into one disc.
		local mx = (frost.x + sky.x) / 2
		local mz = (frost.z + sky.z) / 2
		local df = math.sqrt((mx - frost.x) ^ 2 + (mz - frost.z) ^ 2)
		local ds = math.sqrt((mx - sky.x) ^ 2 + (mz - sky.z) ^ 2)
		t.ok(df > frost.radius and ds > sky.radius, "the midpoint sits in the gap")
		t.eq(type(TerrainGen.HeightAt(mx, mz)), "number")
	end)

	t.test("corridor props sit off the bed, clear the lodge, and counts stay odd", function()
		local Corridor = t.load("ReplicatedStorage/Shared/World/CorridorPlan")
		local counts = Corridor.Counts()
		t.eq(counts.big % 2, 1, "big " .. tostring(counts.big))
		t.eq(counts.mid % 2, 1, "mid " .. tostring(counts.mid))
		t.eq(counts.small % 2, 1, "small " .. tostring(counts.small))
		t.ok(Corridor.WoodParts() <= GameConfig.MaxWoodPartsServer, "wood parts")
		local lots = Corridor.WoodLots()
		t.eq(#lots, 4, "four wood lots")
		for _, parts in ipairs(lots) do
			t.eq(parts % 2, 1, "each wood lot is an odd handful")
		end
		local lodge = Draft.Lodge
		local function roadOf(name)
			for _, road in ipairs(Draft.Roads) do
				if road.name == name then
					return road
				end
			end
			return nil
		end
		local function distToRoad(x, z, road)
			local best = math.huge
			local pts = road.points
			for i = 2, #pts do
				local a, b = pts[i - 1], pts[i]
				local dx, dz = b.x - a.x, b.z - a.z
				local len2 = dx * dx + dz * dz
				local tdot = 0
				if len2 > 1e-6 then
					tdot = math.clamp(((x - a.x) * dx + (z - a.z) * dz) / len2, 0, 1)
				end
				local px, pz = a.x + dx * tdot, a.z + dz * tdot
				local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
				if d < best then
					best = d
				end
			end
			return best
		end
		for _, marker in ipairs(Corridor.Markers()) do
			local road = roadOf(marker.road)
			if road then
				local d = distToRoad(marker.x, marker.z, road)
				t.ok(
					d >= road.width / 2 + Draft.Corridor.propClearOfBed - 0.05,
					string.format(
						"%s on %s is %.2f off the centre (bed half %.1f)",
						marker.kind,
						marker.road,
						d,
						road.width / 2
					)
				)
			end
			if marker.kind == "tree-belt" or marker.kind == "scatter" then
				local dx, dz = marker.x - lodge.x, marker.z - lodge.z
				t.ok(
					dx * dx + dz * dz >= Draft.Corridor.gateClear * Draft.Corridor.gateClear,
					marker.kind .. " inside the lodge gate clear"
				)
			end
		end
	end)

	t.test("RoadGravel and QuarrySlate are the art-table colours", function()
		t.eq(TerrainGen.MaterialColors.Asphalt:ToHex(), "A8A49C")
		t.eq(TerrainGen.MaterialColors.Slate:ToHex(), "5B5650")
		t.eq(TerrainGen.GravelMaterial, "Asphalt")
	end)
end
