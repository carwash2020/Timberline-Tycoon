--!nocheck
-- Phase 12, day 3: the world slices (trees, roads, regions, town).
-- The first 322 trees keep their X and Z (WorldPlan.spec's fingerprint).
-- Country stands were re-placed because the roads they line got wider.
return function(t)
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BiomeData = t.shared("BiomeData")
	local Vector2 = t.roblox.Vector2

	local function roadNamed(name)
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == name then
				return road
			end
		end
		return nil
	end

	t.test("haul roads, the skyroot road, the forest path and the plot road are the wider widths", function()
		local want = {
			ForestPath = 16,
			HillsRoad = 28,
			SnowRoad = 28,
			VolcanoRoad = 28,
			SkyrootRoad = 24,
			MillRoad = 22,
			LotLoop = 16,
		}
		for name, width in pairs(want) do
			local road = roadNamed(name)
			t.ok(road, name)
			t.eq(road.width, width, name)
		end
		local spurs = 0
		for _, road in ipairs(WorldLayout.Roads) do
			if road.name == "PlotSpur" then
				spurs += 1
				t.eq(road.width, 22, "a homestead lane is a Logging Rig wide")
			end
			t.ok(road.name ~= "PlotRoad" and road.name ~= "PlotLane", "the old plot grid is gone")
		end
		t.eq(spurs, 14, "one lane for each homestead")
	end)

	t.test("the snow and volcano junctions flare, and the flare is pale road", function()
		t.eq(#WorldLayout.Junctions, 2)
		local seen = { [30] = false, [-20] = false }
		for _, junction in ipairs(WorldLayout.Junctions) do
			t.ok(junction.haul, junction.name)
			t.ok(junction.radius >= 28, junction.name .. " is wide enough to turn a rig")
			seen[junction.at.X] = true
			local _, material = TerrainGen.Sample(junction.at.X, junction.at.Y)
			t.eq(material, TerrainGen.GravelMaterial, junction.name .. " is pale")
			-- Twenty studs off the Snow Road's centre, still inside the flare.
			local _, beside = TerrainGen.Sample(junction.at.X + 20, junction.at.Y)
			t.eq(beside, TerrainGen.GravelMaterial, junction.name .. " stays pale off the centreline")
		end
		t.ok(seen[30] and seen[-20], "flares at (30, 450) and (-20, 760)")
	end)

	t.test("a truck-wide way runs past the shops to the Snow Road, and a loop runs south of the lot", function()
		local mill = roadNamed("MillRoad")
		local loop = roadNamed("LotLoop")
		t.eq(mill.points[1], Vector2.new(64, 76))
		t.eq(mill.points[#mill.points], Vector2.new(0, 205))
		t.eq(loop.points[1], Vector2.new(-6, -30))
		t.ok(loop.points[3].Y <= -50, "the loop stays south of the pull-outs")
		t.ok(TerrainGen.RoadClearance(102, 120) < 0, "the mill road is a road")
		t.ok(TerrainGen.RoadClearance(80, -58) < 0, "the lot loop is a road")
		-- The street is 22 wide, lamps and benches sit on the grass beside it.
		local town = WorldPlan.Town()
		local function near(x, z)
			for _, cf in ipairs(town.lamps) do
				local p = cf.Position
				if math.abs(p.X - x) < 0.05 and math.abs(p.Z - z) < 0.05 then
					return true
				end
			end
			return false
		end
		t.ok(near(-92, 54) and near(30, 92), "street lamps are set back")
		for _, prop in ipairs(town.props) do
			local p = prop.cframe.Position
			if prop.name == "Bench" then
				t.ok(p.Z < 62, "a bench is south of the street")
			end
		end
	end)

	t.test("the Snowfields and the Volcano each have one cliff gate, and the hollow has shallow pools", function()
		local function runs(cx, cz, radius, passH)
			local low = {}
			for i = 0, 35 do
				local a = i / 36 * math.pi * 2
				local h = TerrainGen.HeightAt(cx + math.cos(a) * radius, cz + math.sin(a) * radius)
				low[i + 1] = h < passH + 18
			end
			local n, prev = 0, low[36]
			for i = 1, 36 do
				if low[i] and not prev then
					n += 1
				end
				prev = low[i]
			end
			return n
		end
		local snow = BiomeData.Get("snow").area
		local snowRim
		for _, rim in ipairs(WorldLayout.Rims) do
			if rim.kind == "snow" then
				snowRim = rim
			end
		end
		local snowR = (snowRim.inner + snowRim.outer) / 2
		local snowPass = TerrainGen.HeightAt(snow.x, snow.z - snowR)
		local snowWall = TerrainGen.HeightAt(snow.x + snowR, snow.z)
		t.ok(snowWall > snowPass + 8, string.format("snow wall %.1f over the pass %.1f", snowWall, snowPass))
		t.eq(runs(snow.x, snow.z, snowR, snowPass), 1, "one pass into the Snowfields")
		local _, snowMat = TerrainGen.Sample(snow.x + snowR, snow.z)
		t.eq(snowMat, "Rock", "the snow ring is brown rock")

		local volcano = BiomeData.Get("volcano").area
		local volRim
		for _, rim in ipairs(WorldLayout.Rims) do
			if rim.kind == "volcano" then
				volRim = rim
			end
		end
		local volR = (volRim.inner + volRim.outer) / 2
		local aim = Vector2.new(-150, -120).Unit
		local passAt = Vector2.new(volcano.x, volcano.z) + aim * volR
		local wallAt = Vector2.new(volcano.x, volcano.z) + Vector2.new(-aim.Y, aim.X) * volR
		local volPass = TerrainGen.HeightAt(passAt.X, passAt.Y)
		local volWall = TerrainGen.HeightAt(wallAt.X, wallAt.Y)
		t.ok(volWall > volPass + 8, string.format("volcano rim %.1f over the gap %.1f", volWall, volPass))
		t.eq(runs(volcano.x, volcano.z, volR, volPass), 1, "one gap in the volcano rim")
		local _, volMat = TerrainGen.Sample(wallAt.X, wallAt.Y)
		t.ok(volMat == "Basalt" or volMat == "Slate", "the volcano rim is dark stone, got " .. tostring(volMat))

		t.ok(#WorldLayout.GrovePools >= 3, "pools in the hollow")
		for _, pool in ipairs(WorldLayout.GrovePools) do
			local surface = TerrainGen.WaterLevelAt(pool.x, pool.z)
			local h = TerrainGen.HeightAt(pool.x, pool.z)
			t.ok(surface ~= nil and h < surface, "a pool holds water")
			t.ok(surface - h < 2.4 and surface - h > 0.3, string.format("shallow (%.2f)", surface - h))
		end
	end)

	t.test("gate signs stand at the snow, volcano and hollow, and the road signs stay four", function()
		local gates = WorldPlan.GateSigns(WorldPlan.BiomeSignText)
		t.eq(#gates, 3)
		local blob = ""
		for _, sign in ipairs(gates) do
			blob ..= sign.text .. "\n"
		end
		t.ok(string.find(blob, "SNOWFIELDS", 1, true), "a snow gate")
		t.ok(string.find(blob, "VOLCANO", 1, true), "a volcano gate")
		t.ok(string.find(blob, "GLOAM", 1, true), "a hollow gate")
		t.eq(#WorldPlan.RoadSigns(function()
			return ""
		end), 4)
	end)

	t.test("brown boulders sit on the open grass, and the forest is wider but still a forest", function()
		local rocks = WorldPlan.MeadowBoulders()
		local mill = WorldLayout.Sawmill
		t.ok(#rocks >= 24, #rocks .. " meadow boulders")
		for _, b in ipairs(rocks) do
			local p = b.position
			local d = Vector2.new(p.X - mill.X, p.Z - mill.Z).Magnitude
			t.ok(not b.snowy and not b.dark, "brown, on grass")
			t.ok(d >= 150 and d <= 270, "on the open lawn")
			t.eq(WorldLayout.ForestCover(p.X, p.Z), 0)
			t.ok(TerrainGen.RoadClearance(p.X, p.Z) > 14, "off the roads")
		end
		t.eq(WorldPlan.ForestSpacing, 21)
		t.eq(WorldPlan.ForestEdgeApart, 45)
		t.eq(WorldPlan.ForestVergeStep, 40)
		local trees = WorldPlan.Trees()
		-- Shelves and lanes take a few country stands (was 772 when every
		-- pad shared one lawn). The floor stays under the live count.
		t.ok(#trees >= 730, #trees .. " trees")
		local wet = 0
		for i = 1, 322 do
			local p = trees[i].position
			if TerrainGen.WaterLevelAt(p.X, p.Z) ~= nil then
				wet += 1
			end
		end
		t.eq(wet, 0, "a saved tree standing in a new pool")
	end)
end
