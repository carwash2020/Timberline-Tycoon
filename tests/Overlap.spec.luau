--!nocheck
-- The one overlap pass (WORLD-SPREAD): nothing on the map shares space with
-- anything else, bar the named hits below. Every one of them involves a FIXED
-- tree (a supply, region, added, strip or first tree: they are never moved or
-- thinned), and rocks and scenery never move either, so they wait for a
-- decision. Every movable tree that overlapped a rock, a scenery piece or a
-- fixed tree is dropped by the thinning rule (TreeSpreadData). A new hit
-- fails this spec with both ids and the coordinates.
return function(t)
	local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
	local OverlapCheck = t.load("ReplicatedStorage/Shared/World/OverlapCheck")

	-- "<tree id> | <other id>" -> why it stays.
	local FIXED = {
		["added#78 emberwood | boulder#22"] = "added tree (Cherry/Willow/region rows are pinned)",
		["region#2 bogcypress | boulder#55"] = "Bayou supply tree",
		["region#43 bogcypress | boulder#7"] = "Bayou supply tree",
		["trees#698 emberwood | boulder#67"] = "Volcano supply tree",
		["reach#5 phantomwood | scenery#60 Outcrop"] = "Petrified Reach tree",
		["strip#2 maple | scenery#71 RuinedCabin"] = "north strip tree",
		["strip#25 birch | scenery#71 RuinedCabin"] = "north strip tree",
		["strip#14 maple | strip#33 birch"] = "north strip pair",
		["strip#15 maple | strip#32 birch"] = "north strip pair",
		["strip#17 maple | strip#40 birch"] = "north strip pair",
		["strip#18 maple | strip#39 birch"] = "north strip pair",
		["trees#238 oak | region#69 ironwood"] = "first tree against a Mesa supply tree",
		["trees#255 oak | region#49 ironwood"] = "first tree against a Mesa supply tree",
	}

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

	t.test("no overlap in any pair except the named fixed-tree hits", function()
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
end
