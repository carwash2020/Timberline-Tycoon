--!nocheck
-- The refill (WORLD-SPREAD, T356): clumps of 3 in treeable 200 stud cells under
-- the floor of 3, on top of every older list, so the map has no empty stretch
-- and holds at least as many trees as main.
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
	local unfilled = WorldPlan._spreadUnfilled

	local MAIN_TOTAL = 1308 -- ground trees on main 73f9547 by tools/tree_report's count
	local SEA = WorldLayout.SeaLevel

	-- Every tree that stands: Trees() minus the thinned, every other list, the
	-- oak clumps, Murph's three oaks and the refill.
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

	t.test(
		"the refill is clumps of 3, appended after the thinning, and replaces what it dropped with a net gain",
		function()
			t.ok(#spread >= TreeSpread.SkipCount() + TreeSpread.NetGain, "plants at least dropped + 6: " .. #spread)
			t.eq(#spread % 3, 0)
			local byZone = {}
			for _, spot in ipairs(spread) do
				t.eq(spot.biome, "wild")
				t.ok(string.sub(spot.zone.id, 1, 7) == "spread:")
				byZone[spot.zone.id] = (byZone[spot.zone.id] or 0) + 1
			end
			for id, n in pairs(byZone) do
				t.eq(n, 3, id)
			end
		end
	)

	t.test("the total is at least main's", function()
		t.ok(#all >= MAIN_TOTAL, string.format("%d trees (main %d)", #all, MAIN_TOTAL))
	end)

	t.test(
		"every refill tree is on legal ground, 10 studs from every other tree, and its wood follows the zone rule",
		function()
			local older = {}
			for _, tr in ipairs(all) do
				table.insert(older, Vector3.new(tr.x, 0, tr.z))
			end
			for _, spot in ipairs(spread) do
				local p = spot.position
				t.ok(TreeFill.Ground(p.X, p.Z), "ground")
				t.ok(TerrainGen.HeightAt(p.X, p.Z) > SEA + 1, "dry")
				local mix = TreeSpread.WoodsNear(p.X, p.Z)
				local ok = false
				for _, e in ipairs(mix) do
					ok = ok or e.woodId == spot.woodId
				end
				t.ok(ok, spot.woodId .. " is in the mix at (" .. math.floor(p.X) .. "," .. math.floor(p.Z) .. ")")
				t.ok(WoodData.Get(spot.woodId) ~= nil)
				t.ok(
					dist(p.X, p.Z, TreeSpread.SpawnX, TreeSpread.SpawnZ) > TreeSpread.SpawnOak or spot.woodId == "oak",
					"oak by the spawn"
				)
			end
			-- 10 studs from everything else (each tree is in `older` once: itself).
			for _, spot in ipairs(spread) do
				local p = spot.position
				local near = 0
				for _, q in ipairs(older) do
					if (q.X - p.X) ^ 2 + (q.Z - p.Z) ^ 2 < TreeSpread.Gap ^ 2 then
						near += 1
					end
				end
				t.ok(near == 1, "a refill tree has a neighbour inside 10 studs")
			end
		end
	)

	-- Land cells by the same test tools/tree_report uses.
	local function landCell(cx, cz)
		local land = 0
		for i = 0, 4 do
			for j = 0, 4 do
				if TerrainGen.HeightAt(cx * 200 + 20 + i * 40, cz * 200 + 20 + j * 40) > SEA + 1 then
					land += 1
				end
			end
		end
		return land >= 8
	end

	-- Cells that stay empty on purpose, and why (each also in `unfilled`).
	local EMPTY = {
		["-4,3"] = "no ground passes TreeFill.Ground and the 10 stud gap",
		["0,-2"] = "the third plot pad's footprint and its 12 stud gap cover the cell",
		["-1,-1"] = "inside the 640 stud circle that is already at its peak: a tree here would raise it",
	}

	t.test("every treeable 200 stud cell holds a tree, bar the named cells", function()
		local counts = {}
		for _, tr in ipairs(all) do
			local key = math.floor(tr.x / 200) .. "," .. math.floor(tr.z / 200)
			counts[key] = (counts[key] or 0) + 1
		end
		for cx = -6, 5 do
			for cz = -6, 5 do
				local key = cx .. "," .. cz
				if landCell(cx, cz) and (counts[key] or 0) == 0 then
					t.ok(EMPTY[key] ~= nil, "cell " .. key .. " is empty and not named")
				end
			end
		end
		for key in pairs(EMPTY) do
			local named = false
			for _, k in ipairs(unfilled) do
				named = named or k == key
			end
			t.ok(named, key .. " is one the refill could not fill: " .. EMPTY[key])
		end
	end)

	t.test(
		"no 100 stud cell holds more than 25 trees bar the four fixed-only cells, and the 640 stud peak does not rise",
		function()
			local cells = {}
			for _, tr in ipairs(all) do
				local key = math.floor(tr.x / 100) .. "," .. math.floor(tr.z / 100)
				cells[key] = (cells[key] or 0) + 1
			end
			local EXEMPT = { ["0,-2"] = 44, ["-5,1"] = 44, ["9,-1"] = 27, ["-1,-3"] = 27 }
			for key, n in pairs(cells) do
				if n > TreeSpread.Cap then
					t.eq(n, EXEMPT[key], "cell " .. key)
				end
			end
			-- The peak before the refill is main's 635 plus the oak clumps.
			local before = {}
			for _, tr in ipairs(all) do
				table.insert(before, tr)
			end
			local function peak(list)
				local best = 0
				for cx = -1200, 1200, 40 do
					for cz = -1200, 1200, 40 do
						local n = 0
						for _, tr in ipairs(list) do
							if (tr.x - cx) ^ 2 + (tr.z - cz) ^ 2 <= 640 * 640 then
								n += 1
							end
						end
						best = math.max(best, n)
					end
				end
				return best
			end
			local without = {}
			local isSpread = {}
			for _, spot in ipairs(spread) do
				isSpread[spot.position.X .. "," .. spot.position.Z] = true
			end
			for _, tr in ipairs(all) do
				if not isSpread[tr.x .. "," .. tr.z] then
					table.insert(without, tr)
				end
			end
			t.ok(peak(all) <= peak(without), string.format("peak %d after, %d before", peak(all), peak(without)))
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
			local palms = 0
			for _, spot in ipairs(WorldPlan.FerryPalms()) do
				palms += 1
				_ = spot
			end
			t.ok(palms >= 6, "Ferry Isle palms")
			t.ok(#WorldPlan.Sky().lumenwood >= 6, "the Sky's Lumenwood")
		end
	)

	t.test("the refill is deterministic, and it keeps clear of the spawn view and the tutorial oaks", function()
		local again = WorldPlan.SpreadTrees()
		t.eq(#again, #spread)
		for i, spot in ipairs(spread) do
			t.eq(again[i].position, spot.position)
		end
		for _, spot in ipairs(spread) do
			for _, g in ipairs(TutorialGrove.Trees) do
				t.ok(dist(spot.position.X, spot.position.Z, g.x, g.z) >= TreeSpread.Gap)
			end
		end
	end)
end
