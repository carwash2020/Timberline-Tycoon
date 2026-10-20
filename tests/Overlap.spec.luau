--!nocheck
-- The one overlap pass (WORLD-SPREAD): nothing on the map shares space with
-- anything else. Every movable tree that overlapped a rock, a scenery piece or a
-- fixed tree is dropped by the thinning rule (TreeSpreadData); the 13 hits that
-- involved fixed trees were fixed by T372's small moves (post-plan override tables in
-- WorldPlan and two StripClumps). Any exemption must be named in FIXED below. A new
-- hit fails this spec with both ids and the coordinates.
return function(t)
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local OverlapCheck = t.load("ReplicatedStorage/Shared/World/OverlapCheck")
	local TreeSpread = t.load("ReplicatedStorage/Shared/World/TreeSpread")

	-- Named exemptions: "<tree id> | <other id>" -> why it stays. None are left: T372
	-- moved the four boulders, the Ruined Cabin, the Reach tree, two Mesa ironwoods and
	-- two north-strip clumps, so every hit of #220's list is gone. A hit added here must
	-- say why, and it fails the spec when it disappears.
	local FIXED = {}

	local function pairId(hit)
		return hit.a.id .. " | " .. hit.b.id
	end

	local grid, counts = OverlapCheck.Build(WorldPlan)
	local results = OverlapCheck.Run(grid)

	t.test("the check really measured something", function()
		t.ok((counts.tree or 0) > 1300, "trees")
		t.ok((counts.boulder or 0) > 50, "boulders")
		t.ok((counts.part or 0) > 500, "building parts")
		t.eq(counts.prop, 27)
		t.eq(#results, 10, "every pair check ran")
	end)

	t.test("no overlap in any pair (the 13 hits of T372 are gone), bar anything named in FIXED", function()
		local seen = {}
		for _, result in ipairs(results) do
			for _, hit in ipairs(result.hits) do
				local id = pairId(hit)
				seen[id] = true
				local s = hit.a.shape
				t.ok(
					FIXED[id] ~= nil,
					string.format(
						"%s: %s vs %s at (%.1f, %.1f), gap %.2f",
						result.title,
						hit.a.id,
						hit.b.id,
						(s.x0 + s.x1) / 2,
						(s.z0 + s.z1) / 2,
						hit.gap
					)
				)
			end
		end
		-- And a named hit that no longer exists means the list is stale.
		for id in pairs(FIXED) do
			t.ok(seen[id], "the named hit is gone, remove it: " .. id)
		end
	end)

	t.test(
		"the town's props no longer overlap each other or the buildings (the Barrel, Crate, SawdustPile and LogPiles)",
		function()
			for _, result in ipairs(results) do
				if string.find(result.title, "^prop") then
					t.eq(#result.hits, 0, result.title)
				end
			end
		end
	)

	t.test("with the override tables applied, OverlapCheck reports 0 hits (old main reported 13)", function()
		local total = 0
		for _, result in ipairs(results) do
			total += #result.hits
		end
		t.eq(total, 0)
	end)

	t.test("the moved spots keep 10 studs from every tree and 2 from every boulder", function()
		local trees = {}
		local function add(list, tag)
			for i, spot in ipairs(list) do
				-- (a thinned tree is not planted)
				if not TreeSpread.Skipped(spot.position.X, spot.position.Z) then
					table.insert(trees, { tag = tag .. "#" .. i, x = spot.position.X, z = spot.position.Z })
				end
			end
		end
		add(WorldPlan.Trees(), "trees")
		add(WorldPlan.StripTrees(), "strip")
		add(WorldPlan.FerryPalms(), "palms")
		add(WorldPlan.RegionTrees(), "region")
		add(WorldPlan.ReachTrees(), "reach")
		add(WorldPlan.AddedTrees(), "added")
		local boulders = WorldPlan.Boulders()
		-- The moved trees: 10 studs (centre to centre) from every other tree, and a trunk
		-- disc (1.8 studs) plus 2 studs from every boulder's own radius (size * 0.86).
		for _, tag in ipairs({ "reach#5", "region#69", "region#49" }) do
			local me
			for _, tr in ipairs(trees) do
				if tr.tag == tag then
					me = tr
				end
			end
			t.ok(me, tag)
			for _, other in ipairs(trees) do
				if other ~= me then
					local d = math.sqrt((other.x - me.x) ^ 2 + (other.z - me.z) ^ 2)
					t.ok(d >= 10, tag .. " is " .. string.format("%.1f", d) .. " from " .. other.tag)
				end
			end
			for i, b in ipairs(boulders) do
				local d = math.sqrt((b.position.X - me.x) ^ 2 + (b.position.Z - me.z) ^ 2) - b.size * 0.86 - 1.8
				t.ok(d >= 2, tag .. " is " .. string.format("%.1f", d) .. " from boulder#" .. i)
			end
		end
		-- The moved boulders: 2 studs from every tree's trunk disc and from every other boulder.
		for _, index in ipairs({ 67, 55, 7, 22 }) do
			local b = boulders[index]
			for _, tr in ipairs(trees) do
				local d = math.sqrt((tr.x - b.position.X) ^ 2 + (tr.z - b.position.Z) ^ 2) - b.size * 0.86 - 1.8
				t.ok(d >= 2, "boulder#" .. index .. " is " .. string.format("%.1f", d) .. " from " .. tr.tag)
			end
			for j, other in ipairs(boulders) do
				if j ~= index then
					local d = math.sqrt((other.position.X - b.position.X) ^ 2 + (other.position.Z - b.position.Z) ^ 2)
						- other.size * 0.86
						- b.size * 0.86
					t.ok(d >= 2, "boulder#" .. index .. " is " .. string.format("%.1f", d) .. " from boulder#" .. j)
				end
			end
		end
	end)
end
