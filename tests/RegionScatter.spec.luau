--!nocheck
-- Lane R: where the scatter goes. Deterministic, in budget, and off everything.
return function(t)
	local RegionScatter = t.load("ReplicatedStorage/Shared/Regions/RegionScatter")
	local BayouData = t.load("ReplicatedStorage/Shared/Regions/BayouData")
	local MesaData = t.load("ReplicatedStorage/Shared/Regions/MesaData")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local BiomeData = t.shared("BiomeData")

	local function treePositions(biome)
		local out = {}
		for _, spot in ipairs(WorldPlan.RegionTrees()) do
			if spot.biome == biome then
				table.insert(out, spot.position)
			end
		end
		return out
	end

	local function sites(region)
		return RegionScatter.Sites(region, treePositions(region), TerrainGen.RoadClearance)
	end

	t.test("the same sites every time, as many as the budget", function()
		local a, b = sites("bayou"), sites("bayou")
		t.eq(#a, BayouData.Budgets.scatterPieces)
		t.eq(a, b)
		local m = sites("mesa")
		t.eq(#m, MesaData.Budgets.scatterPieces)
		t.eq(m, sites("mesa"))
	end)

	t.test("every site is inside its disc, off the roads, the junction, the region's builds and the trees", function()
		for region, data in pairs({ bayou = BayouData, mesa = MesaData }) do
			local disc = BiomeData.RegionDiscs[region]
			local trees = treePositions(region)
			local list = sites(region)
			for i, s in ipairs(list) do
				local d = math.sqrt((s.x - disc.x) ^ 2 + (s.z - disc.z) ^ 2)
				t.ok(d <= disc.radius - 10 + 1e-6, region .. " site " .. i .. " is " .. d .. " from the middle")
				t.ok(TerrainGen.RoadClearance(s.x, s.z) >= 8, region .. " site " .. i .. " is on a road")
				local j = data.Junction
				t.ok(
					math.sqrt((s.x - j.x) ^ 2 + (s.z - j.z) ^ 2) > j.radius + 6,
					region .. " site " .. i .. " is in the junction"
				)
				t.ok(not data.Blocked(s.x, s.z, 4), region .. " site " .. i .. " is in a footprint")
				for _, p in ipairs(trees) do
					t.ok((p.X - s.x) ^ 2 + (p.Z - s.z) ^ 2 >= 25, region .. " site " .. i .. " is under a tree")
				end
				for k = i + 1, #list do
					local o = list[k]
					t.ok((o.x - s.x) ^ 2 + (o.z - s.z) ^ 2 >= 36, region .. " sites " .. i .. " and " .. k .. " touch")
				end
			end
		end
	end)

	t.test("each region uses only its own kinds, all of them", function()
		local function kindsOf(region)
			local seen = {}
			for _, s in ipairs(sites(region)) do
				seen[s.kind] = true
			end
			return seen
		end
		local bayou = kindsOf("bayou")
		for _, k in ipairs(BayouData.ScatterKinds) do
			t.ok(bayou[k], "the Bayou has " .. k)
		end
		local mesa = kindsOf("mesa")
		for _, k in ipairs(MesaData.ScatterKinds) do
			t.ok(mesa[k], "the mesa has " .. k)
		end
		for k in pairs(bayou) do
			t.ok(table.find(BayouData.ScatterKinds, k) ~= nil, k)
		end
	end)
end
