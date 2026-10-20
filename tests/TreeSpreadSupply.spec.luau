--!nocheck
-- Supply trees moved inside their own zone (WORLD-SPREAD, T366): nine trees,
-- listed in TreeSpreadData.Moved, stand elsewhere in their disc. Nothing else
-- about the plan changed: same woods, biomes and zones at every index, the same
-- counts per zone and wood, the same positions at every other index.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local TreeSpreadData = t.shared("World/TreeSpreadData")
	local BiomeData = t.shared("BiomeData")
	local GrowLogic = t.shared("GrowLogic")

	local trees = WorldPlan.Trees()
	local moved = {}
	for _, m in ipairs(TreeSpreadData.Moved) do
		moved[m.index] = m
	end

	local function sum(skip, withPosition)
		local acc = 0
		for i, s in ipairs(trees) do
			if not skip[i] then
				local line = string.format("%d|%s|%s|%s", i, s.woodId, s.biome, if s.zone then s.zone.id else "-")
				if withPosition then
					line ..= string.format(
						"|%d|%d",
						math.floor(s.position.X * 100 + 0.5),
						math.floor(s.position.Z * 100 + 0.5)
					)
				end
				for k = 1, #line do
					acc = (acc * 33 + string.byte(line, k)) % 1000000007
				end
			end
		end
		return acc
	end

	t.test("every index keeps the wood, biome and zone main had, and every other tree its position", function()
		-- T397: the ground moved, so the plan is 1,052 trees (1,041 on main) and the nine
		-- moves were dropped: they were generated against the old plan, and T400 re-plans.
		t.eq(#trees, 1052)
		-- Main's: all 1,041 indices (no positions), and every index but the nine moved ones (with positions).
		t.eq(sum({}, false), 930487032, "wood, biome and zone at every index")
		t.eq(sum(moved, true), 263398849, "positions of the trees that did not move")
		t.eq(#TreeSpreadData.Moved, 0)
	end)

	t.test("per-zone and per-wood counts equal main's, so a re-pin cannot hide a lost tree", function()
		local counts = {}
		for _, s in ipairs(trees) do
			local key = s.biome .. "/" .. s.woodId
			counts[key] = (counts[key] or 0) + 1
		end
		local MAIN = {
			["grove/phantomwood"] = 22,
			["hills/maple"] = 50,
			["hills/pine"] = 80,
			["snow/frostwood"] = 70,
			["starter/birch"] = 26,
			["starter/oak"] = 70,
			["volcano/emberwood"] = 60,
			["wild/birch"] = 174,
			["wild/maple"] = 35,
			["wild/oak"] = 196,
			["wild/pine"] = 269,
		}
		for key, n in pairs(MAIN) do
			t.eq(counts[key], n, key)
		end
		t.eq(counts["hills/maple"] + counts["hills/pine"], 130, "hills supply")
		t.eq(counts["starter/birch"] + counts["starter/oak"], 96, "starter supply")
	end)

	t.test(
		"each moved tree stays in its own zone's disc, keeps its size class, and keeps 10 studs from every tree",
		function()
			local older = {}
			for i, s in ipairs(trees) do
				if not moved[i] and not t.shared("World/TreeSpread").Skipped(s.position.X, s.position.Z) then
					table.insert(older, s.position)
				end
			end
			for _, list in ipairs({
				WorldPlan.StripTrees(),
				WorldPlan.FerryPalms(),
				WorldPlan.RegionTrees(),
				WorldPlan.AddedTrees(),
				WorldPlan.NearGrove(),
			}) do
				for _, s in ipairs(list) do
					table.insert(older, s.position)
				end
			end
			for _, m in ipairs(TreeSpreadData.Moved) do
				local spot = trees[m.index]
				local area = BiomeData.Get(spot.biome).area
				local d = math.sqrt((m.x - area.x) ^ 2 + (m.z - area.z) ^ 2)
				t.ok(d <= area.radius - 6 + 0.01, "tree " .. m.index .. " left its disc")
				t.ok(
					math.abs(spot.position.X - m.x) < 0.01 and math.abs(spot.position.Z - m.z) < 0.01,
					"the plan has it at the data's spot"
				)
				local _, was = GrowLogic.Site(Vector3.new(m.fromX, 0, m.fromZ))
				local _, now = GrowLogic.Site(Vector3.new(m.x, 0, m.z))
				t.eq(now, was, "size class of tree " .. m.index)
				t.ok(was ~= "large", "an anchor never moves")
				t.ok(m.index > WorldPlan.FirstTreeCount(), "never one of the first trees")
				t.ok(TreeFill.Ground(m.x, m.z) and TreeFill.Clear(m.x, m.z), "legal ground")
				for _, p in ipairs(older) do
					t.ok((p.X - m.x) ^ 2 + (p.Z - m.z) ^ 2 >= 99.99, "10 studs from every other tree")
				end
			end
		end
	)

	t.test("the dense cells gave trees up, and no destination cell ends over 22", function()
		local cells = {}
		local function add(x, z)
			local key = math.floor(x / 100) .. "," .. math.floor(z / 100)
			cells[key] = (cells[key] or 0) + 1
		end
		for _, s in ipairs(trees) do
			if not t.shared("World/TreeSpread").Skipped(s.position.X, s.position.Z) then
				add(s.position.X, s.position.Z)
			end
		end
		for _, list in ipairs({
			WorldPlan.StripTrees(),
			WorldPlan.FerryPalms(),
			WorldPlan.Lanternwood(),
			WorldPlan.RegionTrees(),
			WorldPlan.ReachTrees(),
			WorldPlan.AddedTrees(),
			WorldPlan.NearGrove(),
			WorldPlan.SpreadTrees(),
		}) do
			for _, s in ipairs(list) do
				add(s.position.X, s.position.Z)
			end
		end
		-- Before: Hills (-500,100) 44, Starter (-100,-300) 27 and (0,-200) 44.
		t.eq(cells["-5,1"], 46)
		t.eq(cells["-1,-3"], 27)
		t.eq(cells["0,-2"], 44)
		for _, m in ipairs(TreeSpreadData.Moved) do
			local key = math.floor(m.x / 100) .. "," .. math.floor(m.z / 100)
			t.ok(cells[key] <= 22, "destination cell " .. key .. " holds " .. cells[key])
		end
	end)
end
