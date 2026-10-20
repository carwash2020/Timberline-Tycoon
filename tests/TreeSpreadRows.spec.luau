--!nocheck
-- The spread trees (WORLD-SPREAD T356, then T400): WorldPlan.SpreadTrees is the
-- cover plan (TreeSpreadData.Cover, written by tools/tree_cover): clumps of 3 to
-- 5 real trees appended after every older list, each paid for by a relocated
-- wild tree, so the count is main's. tests/TreeCover.spec checks the rules
-- (gaps, buffers, coverage, lanes); this keeps the older guarantees.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local WorldLayout = t.load("ReplicatedStorage/Shared/World/WorldLayout")
	local TerrainGen = t.load("ReplicatedStorage/Shared/World/TerrainGen")
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")
	local BiomeData = t.shared("BiomeData")
	local WoodData = t.shared("WoodData")
	local TutorialGrove = t.shared("TutorialGrove")

	local spread = WorldPlan.SpreadTrees()

	local MAIN_TOTAL = 1408 -- ground trees on main by tools/tree_report's count: the count does not move
	local SEA = WorldLayout.SeaLevel

	-- Every tree that stands: Trees() minus the thinned and relocated, every
	-- other list, the oak clumps and the spread.
	local function planted()
		local out = {}
		local function add(list)
			for _, spot in ipairs(list) do
				if not TreeSpread.Skipped(spot.position.X, spot.position.Z) then
					table.insert(out, { x = spot.position.X, z = spot.position.Z, woodId = spot.woodId })
				end
			end
		end
		add(WorldPlan.Trees())
		add(WorldPlan.StripTrees())
		add(WorldPlan.FerryPalms())
		add(WorldPlan.Lanternwood())
		add(WorldPlan.RegionTrees())
		add(WorldPlan.ReachTrees())
		add(WorldPlan.AddedTrees())
		add(WorldPlan.NearGrove())
		add(spread)
		return out
	end
	local all = planted()

	local function dist(x, z, ox, oz)
		return math.sqrt((x - ox) ^ 2 + (z - oz) ^ 2)
	end

	t.test("the spread is clumps of 3 to 5 (a lone tree only where nothing else fits), appended last", function()
		local byZone = {}
		for _, spot in ipairs(spread) do
			t.eq(spot.biome, "wild")
			t.ok(string.sub(spot.zone.id, 1, 7) == "spread:")
			byZone[spot.zone.id] = (byZone[spot.zone.id] or 0) + 1
		end
		local lone = 0
		for id, n in pairs(byZone) do
			t.ok(n <= 5, id .. " has " .. n)
			t.eq(spread[1].zone.cap ~= nil, true)
			if n < 3 then
				lone += 1
			end
		end
		t.ok(lone <= 25, lone .. " lone trees")
	end)

	t.test("the total is main's: the spread is paid for by relocated wild trees", function()
		t.eq(#all, MAIN_TOTAL, string.format("%d trees (main %d)", #all, MAIN_TOTAL))
	end)

	t.test("every spread tree is on legal ground, dry, and its wood is a real wood", function()
		for _, spot in ipairs(spread) do
			local p = spot.position
			t.ok(TreeFill.Ground(p.X, p.Z), "ground")
			t.ok(TerrainGen.HeightAt(p.X, p.Z) > SEA + 1, "dry")
			t.ok(WoodData.Get(spot.woodId) ~= nil, spot.woodId)
			t.ok(
				dist(p.X, p.Z, TreeSpread.SpawnX, TreeSpread.SpawnZ) > TreeSpread.SpawnOak or spot.woodId == "oak",
				"oak by the spawn"
			)
		end
	end)

	t.test(
		"no 100 stud cell holds more than 25 trees bar the four fixed-only cells, and the 640 stud peak stays at main's",
		function()
			local cells = {}
			for _, tr in ipairs(all) do
				local key = math.floor(tr.x / 100) .. "," .. math.floor(tr.z / 100)
				cells[key] = (cells[key] or 0) + 1
			end
			-- (T366 moved nine supply trees inside their zones: Hills 44 to 37, Starter 27 to 26 and 44 to 43.)
			local EXEMPT = { ["0,-2"] = 43, ["-5,1"] = 37, ["9,-1"] = 27, ["-1,-3"] = 26 }
			for key, n in pairs(cells) do
				if n > TreeSpread.Cap then
					t.eq(n, EXEMPT[key], "cell " .. key)
				end
			end
			local best = 0
			for cx = -1200, 1200, 40 do
				for cz = -1200, 1200, 40 do
					local n = 0
					for _, tr in ipairs(all) do
						if (tr.x - cx) ^ 2 + (tr.z - cz) ^ 2 <= 640 * 640 then
							n += 1
						end
					end
					best = math.max(best, n)
				end
			end
			print("[TreeSpreadRows] the densest 640 stud circle holds " .. best .. " trees (main 635)")
			t.ok(best <= 635, "peak " .. best)
		end
	)

	t.test(
		"Bayou and Mesa keep at least 6 trees per 10,000 square studs, every zone has its trees, Ferry Isle and the Sky too",
		function()
			local function within(cx, cz, radius)
				local n = 0
				for _, tr in ipairs(all) do
					if dist(tr.x, tr.z, cx, cz) <= radius then
						n += 1
					end
				end
				return n
			end
			for id, d in pairs(BiomeData.RegionDiscs) do
				local per = within(d.x, d.z, d.radius) / (math.pi * d.radius ^ 2) * 10000
				t.ok(per >= 6, id .. " has " .. string.format("%.1f", per) .. " per 10,000")
			end
			for _, id in ipairs({ "starter", "hills", "snow", "volcano", "grove" }) do
				local a = BiomeData.Get(id).area
				t.ok(within(a.x, a.z, a.radius) >= 10, id)
			end
			t.ok(#WorldPlan.FerryPalms() >= 6, "Ferry Isle palms")
			t.ok(#WorldPlan.Sky().lumenwood >= 6, "the Sky's Lumenwood")
		end
	)

	t.test("the spread is deterministic, and it keeps clear of the tutorial oaks", function()
		local again = t.loader():load("ReplicatedStorage/Shared/World/WorldPlan").SpreadTrees()
		t.eq(#again, #spread)
		for i, spot in ipairs(spread) do
			t.eq(again[i].position, spot.position)
			for _, g in ipairs(TutorialGrove.Trees) do
				t.ok(dist(spot.position.X, spot.position.Z, g.x, g.z) >= 10)
			end
		end
		_ = Vector3
	end)
end
