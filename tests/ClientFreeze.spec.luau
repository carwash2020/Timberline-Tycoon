--!nocheck
-- The client freeze ("TreeFill:380: Script timeout" every 10 s, "WeatherController
-- Start took 11.28s"), and the forest that came in all at once after ten seconds.
-- Studio cannot run here, so this proves the causes with work counters and
-- equivalence checks in Lune (what still needs Studio: PHASE2_NOTES.md, "Client
-- freeze"):
--   * TreeFill.takenNear is a hash grid: same answer as the old scan on seeded
--     random points, and the work per query stays flat as the world grows.
--   * WorldPlan.Trees (10 s of work in Lune) is planned once however many callers
--     ask; a caller that arrives while it is being worked out waits for that one
--     build; the callers that only decorate (NatureData.FromWorldPlan) never
--     start it and never wait on it.
--   * NatureData.FromWorldPlan is worked out once per plan, not per call.
--   * Every planner gives the frame back all through its work (no stretch longer
--     than a slice and a little), and the plan is the same trees, in the same
--     order, as before (a pinned checksum from main).
--   * The town's trees (round the spawn) are handed over first, the rest as each
--     batch is planned.
--   * WeatherController.Start returns without yielding and without asking the
--     plan for its trees.
return function(t)
	local roblox = t.roblox
	local Vector3 = roblox.Vector3
	local TreeFill = t.load("ReplicatedStorage/Shared/World/TreeFill")
	local NatureData = t.shared("NatureData")
	local TimeSlice = t.shared("TimeSlice")

	local function lcg(seed)
		local s = seed
		return function()
			s = (s * 1103515245 + 12345) % 2147483648
			return s / 2147483648
		end
	end

	-- WorldPlan.Trees() on main before this change: the same 1,041 trees, in the
	-- same order, with the same woods, biomes, zones and positions.
	-- Re-pinned (WORLD-SPREAD T366): supply trees moved within their zone to thin
	-- dense cells, counts unchanged (TreeSpreadData.Moved, 9 trees). 449351915 before.
	-- T397: re-pinned on purpose: the ground moved (hills, roads, plots, store pads), so the plan is 1,052 trees.
	-- T409: same 1,052 trees at the same X and Z (the first batch is still placed on the classic
	-- ground, and the later batches are chosen on the pre-valley ground). Y is the valley.
	-- 10199207 before T409; 12618450 was the valley before the mine roof, volcano wall,
	-- ferry shore and shelf ease. Those sit under some trunks, so Y moved again.
	local PLAN_COUNT = 1052
	-- Heights only this time. 623119780 was the pre-hills plan; 10199207 was the hills plan.
	-- T413: X and Z stay (the plan bed and the tree clearance do). A few trunks
	-- in the new flat shoulder took the drive's height. 254093984 before.
	local PLAN_CHECKSUM = 205735288
	local function checksum(trees)
		local h = 0
		for i, s in ipairs(trees) do
			local line = string.format(
				"%d|%s|%s|%s|%d|%d|%d",
				i,
				s.woodId,
				s.biome,
				s.zone and s.zone.id or "-",
				math.floor(s.position.X * 1000 + 0.5),
				math.floor(s.position.Y * 1000 + 0.5),
				math.floor(s.position.Z * 1000 + 0.5)
			)
			for k = 1, #line do
				h = (h * 33 + string.byte(line, k)) % 1000000007
			end
		end
		return h
	end

	---------------------------------------------------------------------------
	-- takenNear
	---------------------------------------------------------------------------

	t.test("takenNear: the grid answers exactly as the old scan, on seeded random points", function()
		local rand = lcg(20261011)
		local taken = {}
		local gaps = { 3, 10, 10.5, 16, 17, 25, 40 }
		local asked, yes = 0, 0
		for added = 1, 1300 do
			-- Spread over a 2000-stud square, negative coordinates and cell edges
			-- (multiples of 16) included.
			local x, z = (rand() - 0.5) * 2000, (rand() - 0.5) * 2000
			if added % 17 == 0 then
				x = math.floor(x / 16) * 16
			end
			if added % 19 == 0 then
				z = math.floor(z / 16) * 16
			end
			table.insert(taken, Vector3.new(x, 0, z))
			if added % 20 == 0 then
				for _ = 1, 30 do
					local gap = gaps[math.floor(rand() * #gaps) + 1]
					local qx, qz
					if rand() < 0.5 then
						qx, qz = (rand() - 0.5) * 2000, (rand() - 0.5) * 2000
					else
						-- Close to a taken spot, on both sides of the gap.
						local p = taken[math.floor(rand() * #taken) + 1]
						local a, d = rand() * math.pi * 2, gap * (0.7 + rand() * 0.6)
						qx, qz = p.X + math.cos(a) * d, p.Z + math.sin(a) * d
					end
					local want = TreeFill.TakenNearScan(taken, qx, qz, gap)
					t.eq(
						TreeFill.TakenNear(taken, qx, qz, gap),
						want,
						string.format("(%.2f, %.2f) gap %s", qx, qz, gap)
					)
					asked += 1
					yes += if want then 1 else 0
				end
			end
		end
		t.ok(yes > 100 and asked - yes > 100, "both answers were exercised: " .. yes .. " near of " .. asked)
	end)

	t.test("takenNear: the gap is strict (exactly the gap away is not near) and a cleared list starts over", function()
		local taken = { Vector3.new(0, 0, 0) }
		t.eq(TreeFill.TakenNear(taken, 10, 0, 10), false)
		t.eq(TreeFill.TakenNear(taken, 9.999, 0, 10), true)
		t.eq(TreeFill.TakenNear(taken, -9.999, 0, 10), true)
		t.eq(TreeFill.TakenNear(taken, 0, -10, 10), false)
		-- The lists only ever grow, but one that shrank starts the index over.
		table.insert(taken, Vector3.new(100, 0, 100))
		table.insert(taken, Vector3.new(200, 0, 200))
		t.eq(TreeFill.TakenNear(taken, 200, 205, 10), true)
		table.clear(taken)
		table.insert(taken, Vector3.new(500, 0, 500))
		t.eq(TreeFill.TakenNear(taken, 200, 205, 10), false)
		t.eq(TreeFill.TakenNear(taken, 500, 505, 10), true)
	end)

	t.test("takenNear: the work per query stays flat as the world grows (a grid, not a scan)", function()
		local function perQuery(n, side)
			local rand = lcg(77)
			local taken = {}
			for _ = 1, n do
				table.insert(taken, Vector3.new((rand() - 0.5) * side, 0, (rand() - 0.5) * side))
			end
			TreeFill.TakenNear(taken, 0, 0, 10) -- builds the index
			local stats = TreeFill.Stats
			local calls0, checks0 = stats.takenNearCalls, stats.takenNearChecks
			for _ = 1, 4000 do
				TreeFill.TakenNear(taken, (rand() - 0.5) * side, (rand() - 0.5) * side, 10)
			end
			return (stats.takenNearChecks - checks0) / (stats.takenNearCalls - calls0)
		end
		-- Realistic: the world's 1,200+ trees over its 2,000-stud square; then four
		-- times the trees over four times the ground (the scan would cost four times).
		local small = perQuery(1300, 2000)
		local large = perQuery(5200, 4000)
		print(
			string.format(
				"takenNear: %.2f distance checks a query at 1,300 trees (the scan: 1,300); %.2f at 5,200 (5,200)",
				small,
				large
			)
		)
		t.ok(small < 1300 / 40, "far under the scan's 1,300: " .. small)
		t.ok(large < 5200 / 160, "far under the scan's 5,200: " .. large)
		t.ok(large < small * 2 + 1, "flat as the world grows: " .. small .. " then " .. large)
	end)

	---------------------------------------------------------------------------
	-- NatureData.FromWorldPlan: once per plan, and never the trees' cost
	---------------------------------------------------------------------------

	t.test("FromWorldPlan is worked out once per plan, however many times it is asked", function()
		local calls = {}
		local function counted(name, fn)
			return function(...)
				calls[name] = (calls[name] or 0) + 1
				return fn(...)
			end
		end
		local ready = false
		local plan = {
			TreesReady = function()
				return ready
			end,
			GroveDiscs = counted("GroveDiscs", function()
				return { { cx = 10, cz = 20, radius = 30 } }
			end),
			Crater = counted("Crater", function()
				return Vector3.new(0, 0, 0), 20
			end),
			PointsOfInterest = counted("PointsOfInterest", function()
				return { { id = "Cinder", kind = "Cave", cframe = roblox.CFrame.new(5, 12, 7) } }
			end),
		}
		local first, firstComplete
		for i = 1, 200 do
			local zones, complete = NatureData.FromWorldPlan(plan)
			if i == 1 then
				first, firstComplete = zones, complete
			end
			t.ok(rawequal(zones, first), "the same list every time")
		end
		t.eq(firstComplete, false, "the plan's trees are not ready: no caves yet")
		t.eq(calls.GroveDiscs, 1, "the groves were read once, not 200 times")
		t.eq(calls.Crater, 1)
		t.eq(calls.PointsOfInterest, nil, "the points of interest (placed against every tree) are not asked for yet")
		local kinds = {}
		for _, z in ipairs(first) do
			kinds[z.kind] = (kinds[z.kind] or 0) + 1
		end
		t.eq(kinds.cave, nil)
		ready = true
		local zones, complete
		for _ = 1, 200 do
			zones, complete = NatureData.FromWorldPlan(plan)
		end
		t.eq(complete, true)
		t.eq(calls.PointsOfInterest, 1, "asked once, when the plan was ready")
		t.eq(calls.GroveDiscs, 2, "the rest worked out again once, to add the caves")
		local caves = 0
		for _, z in ipairs(zones) do
			caves += if z.kind == "cave" then 1 else 0
		end
		t.eq(caves, 1)
		-- And once complete it stays so: no more work.
		for _ = 1, 200 do
			NatureData.FromWorldPlan(plan)
		end
		t.eq(calls.PointsOfInterest, 1)
		t.eq(calls.GroveDiscs, 2)
		-- A plan with no TreesReady (a stub) is always ready, as before.
		local _, always = NatureData.FromWorldPlan({
			PointsOfInterest = function()
				return {}
			end,
		})
		t.eq(always, true)
	end)

	---------------------------------------------------------------------------
	-- The plan itself
	---------------------------------------------------------------------------

	t.test(
		"the plan is the same 1,041 trees in the same order as main's (grid, hooks and streaming change no tree)",
		function()
			local WorldPlan = t.load("ReplicatedStorage/Shared/World/WorldPlan")
			local trees = WorldPlan.Trees()
			t.eq(#trees, PLAN_COUNT)
			t.eq(checksum(trees), PLAN_CHECKSUM, "woods, biomes, zones and positions, in order")
			t.ok(rawequal(WorldPlan.Trees(), trees), "cached")
			t.ok(
				rawequal(WorldPlan.Boulders(), WorldPlan.Boulders()),
				"the boulders are worked out once (0.6 s each time before)"
			)
			t.ok(
				rawequal(WorldPlan.MeadowBoulders(), WorldPlan.MeadowBoulders()),
				"the meadow boulders are worked out once (0.7 s each time before)"
			)
			t.eq(#WorldPlan.FirstTrees(), WorldPlan.FirstTreeCount())
			t.ok(WorldPlan.TreesReady())
		end
	)

	-- A tiny scheduler: threads are coroutines, a frame resumes each live one
	-- once, and task.wait / the slice's wait yield to the next frame.
	local function scheduled(onFrame)
		local frame = 0
		local threads = {}
		local sched = {
			frames = function()
				return frame
			end,
		}
		function sched.spawn(name, startFrame, fn)
			table.insert(threads, { name = name, from = startFrame, co = coroutine.create(fn), longest = 0 })
		end
		function sched.run(mostFrames)
			local alive = true
			while alive and frame < mostFrames do
				frame += 1
				alive = false
				for _, th in ipairs(threads) do
					if coroutine.status(th.co) ~= "dead" then
						alive = true
						if frame >= th.from then
							local started = os.clock()
							local ok, err = coroutine.resume(th.co, 0.016)
							th.longest = math.max(th.longest, os.clock() - started)
							assert(ok, th.name .. ": " .. tostring(err))
						end
					end
				end
				if onFrame then
					onFrame(frame)
				end
			end
			return threads
		end
		return sched
	end

	t.test("one build however many ask: paused through, shared, the decorators never wait on it", function()
		local sched
		local loader = t.loader({
			globals = {
				task = {
					wait = function()
						return coroutine.yield("wait") or 0.016
					end,
					spawn = function(fn, ...)
						return coroutine.wrap(fn)(...)
					end,
				},
			},
		})
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		local Fill = loader:load("ReplicatedStorage/Shared/World/TreeFill")
		local Nature = loader:load("ReplicatedStorage/Shared/NatureData")
		-- One-off start-up of the town (shared with TownMarkers on the client, 0.2 s in
		-- Lune), warmed apart so the stretches measured below are the planners' loops.
		WorldPlan.Town()

		local pauses, pausesAtFirstEmit, emitted = 0, nil, {}
		local seen = {}
		local sliceGap, last, longestGap = 0, os.clock(), 0
		local slice = TimeSlice.new({
			budget = 0.008,
			wait = function()
				longestGap = math.max(longestGap, os.clock() - last)
				coroutine.yield("frame")
				last = os.clock()
			end,
		})
		local function pause()
			pauses += 1
			slice.step()
		end
		local resultA, resultC
		local decorators = { partial = 0, complete = 0, firstComplete = nil, caves = 0, partialCaves = 0, longest = 0 }
		sched = scheduled()
		local treesStarted = false
		sched.spawn("planner", 1, function()
			WorldPlan.WithPause(pause, function()
				WorldPlan.FirstTrees()
				return nil
			end)
			treesStarted = true
			resultA = WorldPlan.Trees(pause, function(batch)
				pausesAtFirstEmit = pausesAtFirstEmit or pauses
				table.insert(emitted, batch)
				for _, spot in ipairs(batch) do
					t.ok(not seen[spot], "a tree is handed over once")
					seen[spot] = true
				end
			end)
		end)
		-- The weather's and the wildlife's cave zones: asked every frame, from frame 3.
		sched.spawn("decorators", 3, function()
			while not decorators.firstComplete do
				local started = os.clock()
				local zones, complete = Nature.FromWorldPlan(WorldPlan)
				-- (The first ask also loads the plan's smaller planners and their modules.)
				if decorators.partial > 0 or decorators.firstComplete then
					decorators.longest = math.max(decorators.longest, os.clock() - started)
				end
				local caves = 0
				for _, z in ipairs(zones) do
					caves += if z.kind == "cave" then 1 else 0
				end
				if complete then
					decorators.firstComplete = sched.frames()
					decorators.caves = caves
				else
					decorators.partial += 1
					decorators.partialCaves = caves
				end
				coroutine.yield("frame")
			end
			decorators.complete = 1
		end)
		-- Another caller of the whole plan, mid-build (it used to start the seconds of
		-- work again, and the client froze for each).
		sched.spawn("second caller", 5, function()
			while not treesStarted do
				coroutine.yield("frame")
			end
			for _ = 1, 10 do
				coroutine.yield("frame")
			end
			resultC = WorldPlan.Trees()
		end)
		local threads = sched.run(20000)

		for _, th in ipairs(threads) do
			t.eq(coroutine.status(th.co), "dead", th.name .. " finished")
		end

		t.eq(Fill.Stats.extraRuns, 1, "the fill was planned once, for three callers")
		t.ok(rawequal(resultA, resultC), "the second caller got the first's plan")
		t.eq(#resultA, PLAN_COUNT)
		t.eq(checksum(resultA), PLAN_CHECKSUM, "paused and streamed: the same trees in the same order")
		t.ok(decorators.partial > 20, "the decorators ran " .. decorators.partial .. " frames without the plan's trees")
		t.ok(
			decorators.caves > decorators.partialCaves,
			"...without the plan's cave points of interest ("
				.. decorators.partialCaves
				.. " zones), which joined once it was ready ("
				.. decorators.caves
				.. ")"
		)
		t.ok(
			decorators.longest < 0.05,
			"asking never costs the plan's seconds: longest " .. string.format("%.1f ms", decorators.longest * 1000)
		)

		-- No stretch longer than a slice and a little: the frame goes back all through.
		print(
			string.format(
				"plan: %d pauses, %d frames, longest stretch between yields %.1f ms (Lune), town trees handed over at pause %d of %d",
				pauses,
				sched.frames(),
				longestGap * 1000,
				pausesAtFirstEmit or -1,
				pauses
			)
		)
		t.ok(pauses > 20000, pauses .. " pauses: the work is offered back constantly")
		t.ok(sched.frames() > 100, sched.frames() .. " frames of work")
		t.ok(longestGap < 0.1, string.format("longest stretch %.1f ms (a slice is 8)", longestGap * 1000))

		-- The starter area first: the town's trees are the first batch handed over,
		-- well before the bulk of the work, and everything after the first batch is
		-- handed over exactly once.
		t.ok(#emitted >= 3, #emitted .. " batches")
		for _, spot in ipairs(emitted[1]) do
			t.ok(string.sub(spot.zone.id, 1, 5) == "town:", "the first batch is the town's: " .. spot.zone.id)
		end
		t.ok(
			pausesAtFirstEmit < pauses * 0.4,
			"the town's trees came after " .. pausesAtFirstEmit .. " of " .. pauses .. " pauses"
		)
		local total = #WorldPlan.FirstTrees()
		for _, batch in ipairs(emitted) do
			total += #batch
		end
		t.eq(total, #resultA, "first batch + every batch handed over = the plan")
		local first = {}
		for _, spot in ipairs(WorldPlan.FirstTrees()) do
			first[spot] = true
		end
		for spot in pairs(seen) do
			t.ok(not first[spot], "no first-batch tree is handed over twice")
		end
	end)

	t.test("WithPause: bound to the calling thread, restored after an error, results unchanged", function()
		local loader = t.loader({ isolated = true })
		local WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		local seen = 0
		local ok, err = pcall(function()
			return WorldPlan.WithPause(function()
				seen += 1
			end, function()
				error("boom")
			end)
		end)
		t.ok(not ok and string.find(tostring(err), "boom", 1, true) ~= nil, "the error comes out")
		-- (Not inside WithPause any more: a planner run now offers nothing.)
		local before = seen
		WorldPlan.MeadowBoulders()
		t.eq(seen, before, "the pause is not called once WithPause has returned")
		-- Another thread's work is never suspended on this thread's pause. (The first
		-- planner run loads its modules, which Lune's loader does with a yielding file
		-- read, so one runs here first.)
		WorldPlan.FirstTrees()
		local other = 0
		local result = WorldPlan.WithPause(function()
			other += 1
		end, function()
			local co = coroutine.wrap(function()
				return WorldPlan.Boulders()
			end)
			return co()
		end)
		t.eq(other, 0, "a planner run on another thread did not call this thread's pause")
		t.ok(#result > 0)
	end)

	---------------------------------------------------------------------------
	-- Client modules
	---------------------------------------------------------------------------

	t.test("no client script asks WorldPlan.Trees for its trees without a pause", function()
		local fs = require("@lune/fs")
		local dir = "src/StarterPlayer/StarterPlayerScripts"
		for _, entry in ipairs(fs.readDir(dir)) do
			if string.match(entry, "%.luau$") then
				local source = fs.readFile(dir .. "/" .. entry)
				for call in string.gmatch(source, "WorldPlan%.Trees%(([^%)]*)%)") do
					t.ok(call ~= "", entry .. " calls WorldPlan.Trees() with no pause: seconds of work on the client")
				end
			end
		end
	end)

	t.test("WeatherController.Start returns without yielding and never asks for the plan's trees", function()
		local Instance = roblox.Instance
		local ws = Instance.new("Workspace")
		local deferred = {}
		local asked = { trees = 0, pois = 0, trace = {} }
		local plan = {
			TreesReady = function()
				return false
			end,
			Trees = function()
				asked.trees += 1
				return {}
			end,
			PointsOfInterest = function()
				asked.pois += 1
				return {}
			end,
			GroveDiscs = function()
				return {}
			end,
		}
		local clockNow = 0
		local loader = t.loader({
			services = {
				Players = { LocalPlayer = nil },
				Lighting = {},
				SoundService = {},
				RunService = {
					IsStudio = function()
						return false
					end,
					Heartbeat = {
						Connect = function() end,
					},
					RenderStepped = {
						Connect = function() end,
					},
				},
			},
			mocks = {
				WorldPlan = plan,
				SoundData = {
					Make = function()
						return nil
					end,
					PlayAt = function() end,
				},
				Net = {
					Remote = function()
						return { OnClientEvent = { Connect = function() end } }
					end,
				},
				CameraShake = {},
				Quality = {
					Budget = function()
						return { CosmeticHz = 60, WeatherRate = 1 }
					end,
				},
				LightingController = {
					Environment = function()
						return {}
					end,
				},
			},
			globals = {
				workspace = ws,
				task = {
					spawn = function(fn, ...)
						-- (An error in a spawned thread only reaches the output.)
						coroutine.resume(coroutine.create(fn), ...)
					end,
					defer = function(fn)
						table.insert(deferred, fn)
					end,
					wait = function()
						coroutine.yield()
					end,
				},
				print = function() end,
			},
		})
		local WeatherController = loader:load("StarterPlayer/StarterPlayerScripts/WeatherController")
		local co = coroutine.create(WeatherController.Start)
		local ok, err = coroutine.resume(co)
		t.ok(ok, tostring(err))
		t.eq(coroutine.status(co), "dead", "Start ran to its end in one go: it never yielded")
		t.eq(asked.trees, 0, "Start did not ask for the plan's trees")
		t.eq(asked.pois, 0, "...nor for the points of interest placed against them")
		t.ok(#deferred >= 1, "the aurora (which reads the zone list) is off Start's path")
		-- Running what Start left for later: still no trees, no points of interest.
		for _, fn in ipairs(deferred) do
			fn()
		end
		t.eq(asked.trees, 0)
		t.eq(asked.pois, 0, "the zone list is built without the caves until the plan is ready")
		t.ok(clockNow == 0)
	end)
end
