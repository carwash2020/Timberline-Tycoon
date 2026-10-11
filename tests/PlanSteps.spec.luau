--!nocheck
-- WorldPlan's filler steps (the ones ForestFiller works through on the client
-- right after the player is in): each used to run to the end in a single frame.
-- Measured in Lune (11 October 2026, a counter in the pause): Scenery 2.1 s,
-- the boulder clusters 0.6 s, the country stands 0.5 s, the forest's trees
-- 0.4 s, the filler clutter 0.9 s (Studio's client is slower again), so the
-- screen stood still for seconds right as the loading card faded. Each now
-- takes a `pause` (a time slice's step) and offers the frame back between
-- small units of work. The plan itself must not change: the same spots, in
-- the same order, with or without a pause (the server and every client agree
-- on it).
return function(t)
	local function world()
		local loader = t.loader({ isolated = true })
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		-- The first 322 trees are the one step left unpaused (they fill the
		-- shared grove discs): worked out first, as the client's AmbientLife and
		-- WeatherController already do at their Start.
		WorldPlan.FirstTreeCount()
		return WorldPlan
	end

	-- Positions in WorldPlan.FillerSteps.
	local SCENERY, STANDS, CLUSTERS, FOREST, TREES, CLUTTER = 2, 3, 4, 7, 8, 9

	local plain = world()
	local paused = world()
	local offered = {}

	t.test("every filler step is there, and takes a pause", function()
		t.eq(#paused.FillerSteps, 9, "the step list ForestFiller walks")
		for i, step in ipairs(paused.FillerSteps) do
			t.eq(type(step), "function", "step " .. i)
		end
	end)

	t.test("the steps offer the frame back often: thousands of small units, not one lump", function()
		local names = {
			[SCENERY] = "Scenery",
			[STANDS] = "CountryStands",
			[CLUSTERS] = "BoulderClusters",
			[FOREST] = "ForestTrees",
			[CLUTTER] = "Clutter",
		}
		for i, step in ipairs(paused.FillerSteps) do
			local name = names[i] or ("step " .. i)
			offered[name] = 0
			step(function()
				offered[name] += 1
			end)
		end
		-- Each floor is far below what the step offers today (Scenery 3,300;
		-- stands 2,300; clusters 1,350; forest 1,100; clutter 1,600) and far above
		-- one lump: a step that stops offering the frame fails here.
		t.ok(offered.Scenery >= 1000, "Scenery offered the frame " .. offered.Scenery .. " times")
		t.ok(offered.CountryStands >= 500, "CountryStands " .. offered.CountryStands)
		t.ok(offered.BoulderClusters >= 300, "BoulderClusters " .. offered.BoulderClusters)
		t.ok(offered.ForestTrees >= 300, "ForestTrees " .. offered.ForestTrees)
		t.ok(offered.Clutter >= 300, "Clutter " .. offered.Clutter)
		t.ok(paused.FillerReady(), "the plan is worked out")
	end)

	t.test("with a pause the plan is exactly the plan without one", function()
		for i = 1, FOREST do
			plain.FillerSteps[i]()
		end
		local a, b = plain.Scenery(), paused.Scenery()
		t.eq(#a, #b, "scenery count")
		for i = 1, #a do
			t.eq(a[i].kind, b[i].kind, "scenery " .. i)
			t.eq(a[i].center, b[i].center, "scenery " .. i .. " centre")
		end
		local sa, sb = plain.CountryStands(), paused.CountryStands()
		t.eq(#sa, #sb, "stand count")
		for i = 1, #sa do
			t.eq(sa[i].center, sb[i].center, "stand " .. i .. " centre")
			t.eq(#sa[i].trees, #sb[i].trees, "stand " .. i .. " trees")
		end
		local ca, cb = plain.BoulderClusters(), paused.BoulderClusters()
		t.eq(#ca, #cb, "cluster count")
		for i = 1, #ca do
			t.eq(ca[i].center, cb[i].center, "cluster " .. i)
			t.eq(#ca[i].rocks, #cb[i].rocks, "cluster " .. i .. " rocks")
		end
		local fa, fb = plain.ForestTrees(), paused.ForestTrees()
		t.eq(#fa, #fb, "forest tree count")
		for i = 1, #fa do
			t.eq(fa[i].position, fb[i].position, "forest tree " .. i)
			t.eq(fa[i].woodId, fb[i].woodId, "forest tree " .. i .. " wood")
		end
	end)

	t.test("a second call, as another thread's would be, gets the cached answer", function()
		t.ok(rawequal(paused.Scenery(function() end), paused.Scenery()), "Scenery")
		t.ok(rawequal(paused.CountryStands(function() end), paused.CountryStands()), "CountryStands")
		t.ok(rawequal(paused.BoulderClusters(function() end), paused.BoulderClusters()), "BoulderClusters")
		t.ok(rawequal(paused.ForestTrees(function() end), paused.ForestTrees()), "ForestTrees")
		local _ = TREES
	end)
end
