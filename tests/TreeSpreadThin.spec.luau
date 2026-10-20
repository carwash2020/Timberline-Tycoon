--!nocheck
-- Thinning (WORLD-SPREAD, T356): the dense 100 stud cells give up movable wild
-- trees, and TreeSpreadData matches the rule that produced it.
return function(t)
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")
	local TreeSpreadData = t.shared("World/TreeSpreadData")
	local GrowLogic = t.shared("GrowLogic")

	local SUPPLY = { starter = true, hills = true, snow = true, volcano = true, grove = true }
	local FIRST = WorldPlan.FirstTreeCount()
	local trees = WorldPlan.Trees()

	local TreeSpreadItems = t.load("ReplicatedStorage/Shared/World/TreeSpreadItems")
	local all, obstacles = TreeSpreadItems.Build(WorldPlan)
	local plan = TreeSpread.PlanSkip(all, obstacles)
	local densityOnly = TreeSpread.PlanSkip(all)

	t.test("TreeSpreadData is exactly what the rule plans today (indices and positions)", function()
		t.eq(#TreeSpreadData.Skipped, #plan)
		for i, index in ipairs(plan) do
			local entry = TreeSpreadData.Skipped[i]
			t.eq(entry.index, index)
			t.ok(
				math.abs(entry.x - trees[index].position.X) < 0.01
					and math.abs(entry.z - trees[index].position.Z) < 0.01,
				"position of " .. index
			)
		end
	end)

	t.test("only movable trees go, never an anchor, never the first 331", function()
		for _, entry in ipairs(TreeSpreadData.Skipped) do
			t.ok(entry.index > FIRST, "not a first tree")
			local spot = trees[entry.index]
			t.ok(not SUPPLY[spot.biome], "not a supply tree")
			local prefix = if spot.zone then string.match(spot.zone.id, "^[^:]*") else "none"
			t.ok(prefix ~= "town" and prefix ~= "plot", "not a town or plot ring tree")
			t.ok(TreeSpread.Skipped(spot.position.X, spot.position.Z), "MapBuilder skips it")
		end
	end)

	t.test("no 100 stud cell holds more than 25 trees after thinning, bar the named fixed-only cells", function()
		local dropped = {}
		for _, index in ipairs(plan) do
			dropped[index] = true
		end
		local cells = {}
		for _, item in ipairs(all) do
			if not (item.index and dropped[item.index]) then
				local key = math.floor(item.x / 100) .. "," .. math.floor(item.z / 100)
				cells[key] = (cells[key] or 0) + 1
			end
		end
		-- Cells over 25 counting fixed trees alone: no movable tree stands there, so
		-- nothing was or could be thinned (the exemption list, confirmed by Manager).
		-- (T366 moved nine supply trees inside their zones: Hills 44 to 37, Starter 27 to 26 and 44 to 43.)
		-- T397: the ground moved the plan; the nine T366 moves were dropped (Hills 46, Starter 27 and 44).
		local EXEMPT = { ["0,-2"] = 44, ["-5,1"] = 46, ["9,-1"] = 27, ["-1,-3"] = 27 }
		for key, n in pairs(cells) do
			if n > TreeSpread.Cap then
				t.ok(EXEMPT[key] ~= nil, "cell " .. key .. " holds " .. n)
				t.eq(n, EXEMPT[key], "an exempt cell is untouched")
			end
		end
		t.ok(cells["5,-8"] <= TreeSpread.Cap, "Red Mesa's 28 is under the cap: " .. tostring(cells["5,-8"]))
	end)

	t.test("thinning by density never drops an anchor; overlap drops add 2 more", function()
		for _, index in ipairs(densityOnly) do
			local _, sizeName = GrowLogic.Site(trees[index].position)
			t.ok(sizeName ~= "large", "tree " .. index .. " is an anchor")
		end
		t.eq(#densityOnly, 21)
		t.eq(#plan, 24)
		t.eq(TreeSpread.PlanSkip(all, obstacles), plan, "deterministic")
	end)

	t.test("no 200 stud cell that held trees is emptied of all of them", function()
		local dropped = {}
		for _, index in ipairs(plan) do
			dropped[index] = true
		end
		local before, after = {}, {}
		for _, item in ipairs(all) do
			local key = math.floor(item.x / 200) .. "," .. math.floor(item.z / 200)
			before[key] = (before[key] or 0) + 1
			if not (item.index and dropped[item.index]) then
				after[key] = (after[key] or 0) + 1
			end
		end
		for key in pairs(before) do
			t.ok(after[key] ~= nil, "cell " .. key .. " lost every tree")
		end
	end)
end
