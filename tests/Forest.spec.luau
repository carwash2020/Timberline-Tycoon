--!nocheck
-- The forest (phase 10, FOR-*): "a forest with the main area open and then
-- the wild landscapes".
--   FOR-01 the band layout (WorldLayout.Forest, WorldLayout.ForestCover):
--          an open hub round the town and the plot district, a forest ring
--          round it with clearings, the wild biomes and lanes left open.

return function(t)
	local Vector2 = t.roblox.Vector2
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local BiomeData = t.shared("BiomeData")
	local Forest = WorldLayout.Forest
	local cover = WorldLayout.ForestCover

	local function report(problems)
		local shown = {}
		for i = 1, math.min(#problems, 8) do
			shown[i] = problems[i]
		end
		return #problems .. " problems: " .. table.concat(shown, "; ")
	end

	local function zone(name)
		for _, z in ipairs(WorldLayout.FlatZones) do
			if z.name == name then
				return z
			end
		end
		error("no flat zone " .. name)
	end

	-- Dry lowland where trees could grow at all.
	local function land(x, z)
		return TerrainGen.WaterLevelAt(x, z) == nil
			and TerrainGen.HeightAt(x, z) < 70
			and WorldLayout.FlatWeight(x, z) <= 0
	end

	---------------------------------------------------------------------------
	-- FOR-01: the band layout
	---------------------------------------------------------------------------

	t.test("FOR-01: the hub is open: town, spawn, sawmill, shops, parking lot, plot district", function()
		local town = WorldPlan.Town()
		local problems = {}
		local function open(x, z, what)
			local c, ring = cover(x, z)
			if c ~= 0 or ring ~= 0 then
				table.insert(problems, string.format("%s (%d, %d): cover %.2f", what, x, z, c))
			end
		end
		for _, name in ipairs({ "Town", "Plots" }) do
			local z0 = zone(name)
			for x = z0.x0, z0.x1, 8 do
				for z = z0.z0, z0.z1, 8 do
					open(x, z, name)
				end
			end
		end
		open(town.spawn.X, town.spawn.Z, "the spawn")
		open(town.sawmill.X, town.sawmill.Z, "the sawmill")
		for _, shop in ipairs(town.shops) do
			open(shop.cframe.X, shop.cframe.Z, shop.kind)
		end
		for i, cf in ipairs(town.parkingSlots) do
			open(cf.X, cf.Z, "parking slot " .. i)
		end
		for _, g in ipairs(town.greenery) do
			open(g.cframe.X, g.cframe.Z, "town " .. g.kind)
		end
		open(town.gondola.X, town.gondola.Z, "the gondola station")
		open(town.campsite.X, town.campsite.Z, "Murph's camp")
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the forest ring wraps the hub: north, south, west and beyond the plots", function()
		-- Walking out from the hub's edge, you're in the forest's canopy
		-- within a few hundred studs, and the lawn round the town is no
		-- wider than the brief's hub (the view from the spawn closes).
		local function firstForest(from, dir, upTo)
			for d = 0, upTo, 4 do
				local p = from + dir * d
				if cover(p.X, p.Y) > 0.5 then
					return d
				end
			end
			return nil
		end
		local spawn = Vector2.new(0, 40)
		-- North past the sawmill, the pine band and the lawn (beside the Snow Road).
		local north = firstForest(spawn + Vector2.new(40, 0), Vector2.new(0, 1), 600)
		t.ok(north and north >= 220 and north <= 380, "north of the spawn the forest starts at " .. tostring(north))
		-- South: the Starter Forest is the ring's front step, the canopy right
		-- round its west and south sides (north-west of it is the town's
		-- lawn, Murph's camp and the spawn; east of it the plot district).
		local starter = BiomeData.Get("starter").area
		for _, deg in ipairs({ 180, 210, 240, 270 }) do
			local dir = Vector2.new(math.cos(math.rad(deg)), math.sin(math.rad(deg)))
			local c = Vector2.new(starter.x, starter.z) + dir * (starter.radius + 8)
			local d = firstForest(c, dir, 200)
			t.ok(d ~= nil and d <= 90, string.format("%d deg off the Starter Forest: forest at %s", deg, tostring(d)))
		end
		-- Beyond the plot district (south) and north of it.
		local plots = zone("Plots")
		for x = plots.x0 + 40, plots.x1 - 40, 120 do
			local d = firstForest(Vector2.new(x, plots.z0), Vector2.new(0, -1), 300)
			t.ok(d ~= nil, string.format("south of the plots at x %d: no forest", x))
		end
		-- Round the Hills (a wild room in the ring): forest north and south of
		-- it (west, it opens onto the river's valley; east, the town's lawn).
		local hills = BiomeData.Get("hills").area
		for _, deg in ipairs({ 90, 270 }) do
			local dir = Vector2.new(math.cos(math.rad(deg)), math.sin(math.rad(deg)))
			local d = firstForest(Vector2.new(hills.x, hills.z) + dir * hills.radius, dir, 260)
			t.ok(d ~= nil, string.format("%d deg off the Hills: no forest", deg))
		end
	end)

	t.test("FOR-01: the ring is 55-70% canopy, with clearings; the wild band only copses", function()
		local inRing, canopy, wild, copse = 0, 0, 0, 0
		for x = -1150, 1150, 23 do
			for z = -1150, 1150, 23 do
				if land(x, z) then
					local c, ring = cover(x, z)
					if ring > 0.5 then
						inRing += 1
						canopy += if c > 0.5 then 1 else 0
					elseif ring == 0 and WorldLayout.HubDistance(x, z) > 0 then
						wild += 1
						copse += if c > 0.5 then 1 else 0
					end
				end
			end
		end
		local share = canopy / inRing
		t.ok(share >= 0.55 and share <= 0.7, string.format("the ring is %.0f%% canopy", share * 100))
		t.ok(inRing > 2500, inRing .. " samples in the ring") -- about 1.4 million sq studs
		local copses = copse / wild
		t.ok(copses >= 0.03 and copses <= 0.12, string.format("the wild band is %.0f%% copse", copses * 100))
	end)

	t.test("FOR-01: every wild biome keeps its own ground: no canopy in it or its margin", function()
		local problems = {}
		for id, margin in pairs(Forest.wild) do
			local a = BiomeData.Get(id).area
			local r = if id == "grove" then WorldLayout.GroveRidge.outer + margin else a.radius + margin
			-- The edge wanders by up to hubNoise, so check inside that.
			local keep = r - Forest.hubNoise
			for _, frac in ipairs({ 0, 0.3, 0.6, 0.9, 1 }) do
				for k = 0, 23 do
					local ang = k / 24 * math.pi * 2
					local x, z = a.x + math.cos(ang) * keep * frac, a.z + math.sin(ang) * keep * frac
					local c = cover(x, z)
					if c > 0 then
						table.insert(problems, string.format("%s (%d, %d): %.2f", id, x, z, c))
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the forest keeps off the water, the beach and the mountains", function()
		local problems = {}
		for x = -1490, 1490, 17 do
			for z = -1490, 1490, 17 do
				local c = cover(x, z)
				if c > 0 then
					if TerrainGen.WaterLevelAt(x, z) ~= nil then
						table.insert(problems, string.format("water at (%d, %d)", x, z))
					end
					local _, material = TerrainGen.Sample(x, z)
					if material == "Sand" then
						table.insert(problems, string.format("sand at (%d, %d)", x, z))
					end
					if math.max(math.abs(x), math.abs(z)) > Forest.mountains then
						table.insert(problems, string.format("mountains at (%d, %d)", x, z))
					end
				end
			end
		end
		-- A margin off the river, the lake and the pond.
		for _, line in ipairs({ WorldLayout.River, WorldLayout.LakeOutflow }) do
			local pts = line.points
			for i = 1, #pts - 1 do
				for s = 0, 1, 0.02 do
					local p = pts[i]:Lerp(pts[i + 1], s)
					local dir = (pts[i + 1] - pts[i]).Unit
					for _, side in ipairs({ -1, 1 }) do
						local q = p + Vector2.new(-dir.Y, dir.X) * side * (line.width / 2 + Forest.water)
						if cover(q.X, q.Y) > 0 then
							table.insert(problems, string.format("by the water at (%d, %d)", q.X, q.Y))
						end
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
	end)

	t.test("FOR-01: the lanes stay open: the spawn's view of the lighthouse, the grove's trail", function()
		local lighthouse = WorldPlan.Lighthouse()
		t.ok(lighthouse ~= nil, "a lighthouse")
		local vista
		for _, lane in ipairs(Forest.lanes) do
			if lane.name == "LighthouseVista" then
				vista = lane
			end
		end
		t.ok(vista ~= nil, "the lighthouse's lane")
		local base = lighthouse.cframe.Position
		local spawn = WorldPlan.Town().spawn
		t.ok((vista.b - Vector2.new(base.X, base.Z)).Magnitude < 3, "the lane ends at the lighthouse")
		t.ok((vista.a - Vector2.new(spawn.X, spawn.Z)).Magnitude < 1, "and starts at the spawn")
		local problems = {}
		for _, lane in ipairs(Forest.lanes) do
			local dir = (lane.b - lane.a).Unit
			local side = Vector2.new(-dir.Y, dir.X)
			for s = 0, 1, 0.01 do
				local p = lane.a:Lerp(lane.b, s)
				for _, off in ipairs({ -0.95, -0.5, 0, 0.5, 0.95 }) do
					local q = p + side * off * lane.half
					local c = cover(q.X, q.Y)
					if c > 0 then
						table.insert(problems, string.format("%s at (%d, %d): %.2f", lane.name, q.X, q.Y, c))
					end
				end
			end
		end
		t.ok(#problems == 0, report(problems))
		-- The grove's trail starts inside its ridge's gap and leads toward town.
		local grove = BiomeData.Get("grove").area
		local trail
		for _, lane in ipairs(Forest.lanes) do
			if lane.name == "GroveTrail" then
				trail = lane
			end
		end
		local fromGrove = (trail.a - Vector2.new(grove.x, grove.z)).Magnitude
		t.ok(fromGrove < WorldLayout.GroveRidge.inner, "the trail starts inside the ridge")
		local toTown = (Vector2.new(0, 110) - Vector2.new(grove.x, grove.z)).Unit
		t.ok((trail.b - trail.a).Unit:Dot(toTown) > 0.99, "and leads toward town")
		t.ok((trail.b - trail.a).Magnitude >= 250, "far enough to clear the ring")
	end)

	t.test("FOR-01: ForestCover is pure: the same on every server, 0..1, ring 0..1", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldLayout")
		for i = 1, 400 do
			local x, z = (i * 97.3) % 2900 - 1450, (i * 61.7) % 2900 - 1450
			local c, ring = cover(x, z)
			local c2, ring2 = again.ForestCover(x, z)
			t.eq(c, c2)
			t.eq(ring, ring2)
			t.ok(c >= 0 and c <= 1 and ring >= 0 and ring <= 1, "in range")
			t.ok(ring == 0 or c <= ring + 1e-9, "a clearing only takes canopy away")
		end
	end)
end
