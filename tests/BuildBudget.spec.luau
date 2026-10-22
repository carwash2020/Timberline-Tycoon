--!nocheck
-- The world build never waits on a mesh (12 October 2026). Connor's Studio
-- log: "[MapBuilder] 4. The shops done in 300.2s" and "meshes: 476 of 685
-- loaded ... (timed out)". Cause: every builder called MeshKit.Create, which
-- yielded in CreateMeshPartAsync for any mesh not cached yet, one mesh after
-- another, behind the 24 preload workers that already held the asset quota.
-- A mesh load is about 0.4 s of network time: 685 of them in a row is minutes.
--
-- Studio cannot run here, so this proves it three ways:
--   1. behaviour: with a held (never-finishing) engine load, a 685-mesh build
--      returns without a single load finishing and without yielding; the
--      meshes then land and every dressing is swapped in, in order:
--      part-built first, mesh load, swap;
--   2. call graph: a source scan of who may call a yielding mesh load;
--   3. the per-phase timing report and the 15 s play budget (BuildTimings).
return function(t)
	local fs = require("@lune/fs")
	local roblox = t.roblox

	local function kit()
		local loader = t.loader()
		local MeshKit = loader:shared("Art/MeshKit")
		MeshKit.Reset()
		MeshKit.Override = nil
		MeshKit.Retries = 0
		-- The engine, held: a load starts only when the spec runs the queued job
		-- and finishes only when the spec says so.
		local jobs = {}
		local clockNow = 0
		local frames = { count = 0 }
		local pumps = {}
		local realPump = MeshKit.Pump
		MeshKit.Pump = function(budget)
			local ran = realPump(budget)
			table.insert(pumps, ran)
			return ran
		end
		MeshKit.Scheduler = {
			spawn = function(fn)
				table.insert(jobs, fn)
			end,
			wait = function()
				frames.count += 1
			end,
			clock = function()
				clockNow += 0.001
				return clockNow
			end,
		}
		local loads = {}
		local failing = {}
		MeshKit.EngineLoad = function(meshId)
			table.insert(loads, meshId)
			if failing[meshId] then
				return nil, "no permission"
			end
			local part = roblox.Instance.new("MeshPart")
			part.Name = "Loaded" .. tostring(meshId)
			return part, nil
		end
		local function runJobs()
			local ran = 0
			while #jobs > 0 do
				local job = table.remove(jobs, 1)
				job()
				ran += 1
			end
			return ran
		end
		return MeshKit,
			{
				jobs = jobs,
				pumps = pumps,
				frames = frames,
				loads = loads,
				failing = failing,
				runJobs = runJobs,
				done = function()
					MeshKit.Pump = realPump
					MeshKit.EngineLoad = nil
					MeshKit.Scheduler = {
						spawn = function(fn)
							fn()
						end,
						wait = function() end,
						clock = os.clock,
					}
					MeshKit.Reset()
				end,
			}
	end

	local SIZE = roblox.Vector3.new(1, 1, 1)

	t.test("Create on an uncached mesh returns nil at once and never yields or loads inline", function()
		local MeshKit, sim = kit()
		local co = coroutine.create(function()
			return MeshKit.Create(111, "Wall", SIZE)
		end)
		local ok, part = coroutine.resume(co)
		t.ok(ok, "no error")
		t.eq(coroutine.status(co), "dead", "Create finished in one go: it never yielded")
		t.eq(part, nil, "no mesh yet: the caller keeps its part-built art")
		t.eq(#sim.loads, 0, "the engine was not touched on the building thread")
		t.eq(#sim.jobs, 1, "the load was queued for the background")
		t.eq(MeshKit.IsPending(111), true)
		sim.runJobs()
		t.eq(sim.loads, { 111 }, "the background thread loaded it")
		t.ok(MeshKit.Create(111, "Wall", SIZE), "a later Create gets the cached mesh")
		sim.done()
	end)

	t.test("CreateAwait is the old yielding call: it loads inline and returns the mesh", function()
		local MeshKit, sim = kit()
		local part = MeshKit.CreateAwait(55, "Wall", SIZE)
		t.ok(part, "the mesh, after waiting for it")
		t.eq(sim.loads, { 55 })
		sim.done()
	end)

	t.test("a build of 685 dressings finishes before any mesh lands, then every one is swapped in", function()
		local MeshKit, sim = kit()
		local order = {}
		local built, swapped = 0, 0
		local models = {}
		local root = roblox.Instance.new("Model")
		-- The "shops step": 685 pieces, each a dress step in the shape every
		-- real dresser has (Create or leave the part-built art, all or none).
		for id = 1, 685 do
			local model = roblox.Instance.new("Model")
			model.Parent = root
			models[id] = model
			local dressed = MeshKit.Attempt(model, function()
				local part = MeshKit.Create(id, "Piece", SIZE)
				if not part then
					return false
				end
				part.Parent = model
				swapped += 1
				return true
			end)
			t.eq(dressed, false, "part-built for now")
			built += 1
		end
		table.insert(order, "build finished")
		t.eq(built, 685)
		t.eq(#sim.loads, 0, "not one mesh load had run when the whole build was done")
		t.eq(swapped, 0)
		-- The meshes arrive (the background pool of 24), and each landing queues
		-- its dressing; the drain thread swaps a slice a frame.
		sim.runJobs()
		table.insert(order, "meshes loaded")
		t.eq(#sim.loads, 685)
		t.eq(MeshKit.SwapStats().ready, 0, "everything has drained")
		local total = 0
		for _, ran in ipairs(sim.pumps) do
			t.ok(ran < 685, "a frame swaps a slice, not everything (" .. ran .. ")")
			total += ran
		end
		t.eq(total, 685, "every dressing ran exactly once")
		t.ok(#sim.pumps > 1 and sim.frames.count > 1, "batched over several frames")
		table.insert(order, "swapped")
		t.eq(swapped, 685)
		t.eq(order, { "build finished", "meshes loaded", "swapped" }, "fallback, then load, then swap")
		for id = 1, 685, 100 do
			t.ok(models[id]:FindFirstChildWhichIsA("MeshPart"), "model " .. id .. " got its mesh")
		end
		t.eq(MeshKit.SwapStats().swapped, 685)
		sim.done()
	end)

	t.test("a dressing waits for every mesh it missed, not just the first", function()
		local MeshKit, sim = kit()
		local model = roblox.Instance.new("Model")
		model.Parent = roblox.Instance.new("Model")
		local calls = 0
		MeshKit.Attempt(model, function()
			calls += 1
			local a = MeshKit.Create(1, "A", SIZE)
			local b = MeshKit.Create(2, "B", SIZE)
			return a ~= nil and b ~= nil
		end)
		t.eq(calls, 1)
		-- Only mesh 1 lands.
		local held = table.remove(sim.jobs, 2) -- the load of mesh 2 is held
		sim.runJobs()
		t.eq(MeshKit.SwapStats().ready, 0, "half the meshes is not enough")
		t.eq(MeshKit.SwapStats().waiting, 1)
		held() -- now mesh 2
		t.eq(MeshKit.SwapStats().ready, 1)
		MeshKit.Pump()
		t.eq(calls, 2, "ran once more, with both meshes")
		t.eq(MeshKit.SwapStats().swapped, 1)
		sim.done()
	end)

	t.test("a mesh that fails stays part-built for good: no swap, no endless retry", function()
		local MeshKit, sim = kit()
		sim.failing[7] = true
		local model = roblox.Instance.new("Model")
		model.Parent = roblox.Instance.new("Model")
		local calls = 0
		MeshKit.Attempt(model, function()
			calls += 1
			return MeshKit.Create(7, "A", SIZE) ~= nil
		end)
		sim.runJobs()
		t.eq(MeshKit.SwapStats().ready, 0)
		t.eq(MeshKit.Pump(), 0)
		t.eq(calls, 1, "never run again")
		t.eq(MeshKit.Create(7, "A", SIZE), nil, "and Create keeps saying nil without asking again")
		t.eq(#sim.loads, 1)
		sim.done()
	end)

	t.test("a dressing whose model was removed before the mesh landed is dropped", function()
		local MeshKit, sim = kit()
		local model = roblox.Instance.new("Model")
		local holder = roblox.Instance.new("Model")
		model.Parent = holder
		local calls = 0
		MeshKit.Attempt(model, function()
			calls += 1
			return MeshKit.Create(9, "A", SIZE) ~= nil
		end)
		model.Parent = nil
		sim.runJobs()
		MeshKit.Pump()
		t.eq(calls, 1, "the removed model is not dressed")
		t.eq(MeshKit.SwapStats().skipped, 1)
		sim.done()
	end)

	t.test("a step that returns true or misses nothing is never scheduled", function()
		local MeshKit, sim = kit()
		local model = roblox.Instance.new("Model")
		model.Parent = roblox.Instance.new("Model")
		t.eq(
			MeshKit.Attempt(model, function()
				return true
			end),
			true
		)
		t.eq(
			MeshKit.Attempt(model, function()
				return false -- failed for another reason (meshId 0): nothing to wait for
			end),
			false
		)
		t.eq(MeshKit.SwapStats().waiting + MeshKit.SwapStats().ready, 0)
		t.eq(#sim.jobs, 0)
		sim.done()
	end)

	t.test("a swap in the build frame puts the model back where it was built, then moves it on", function()
		local MeshKit, sim = kit()
		local model = roblox.Instance.new("Model")
		model.Parent = roblox.Instance.new("Model")
		local seen = {}
		MeshKit.Attempt(model, function()
			table.insert(seen, model:GetPivot())
			return MeshKit.Create(5, "A", SIZE) ~= nil
		end, true)
		local built = model:GetPivot()
		model:PivotTo(roblox.CFrame.new(100, 0, 40)) -- the building is placed in the world
		local placed = model:GetPivot()
		sim.runJobs()
		MeshKit.Pump()
		t.eq(#seen, 2)
		t.eq(seen[2], built, "the swap dressed it in the frame it was built in")
		t.eq(model:GetPivot(), placed, "and it is back where the world put it")
		sim.done()
	end)

	t.test("an error inside a swap is contained and the rest still swap", function()
		local MeshKit, sim = kit()
		local holder = roblox.Instance.new("Model")
		local good = 0
		for i = 1, 3 do
			local model = roblox.Instance.new("Model")
			model.Parent = holder
			MeshKit.Attempt(model, function()
				local part = MeshKit.Create(20 + i, "A", SIZE)
				if part and i == 2 then
					error("boom")
				end
				if part then
					good += 1
				end
				return part ~= nil
			end)
		end
		sim.runJobs()
		MeshKit.Pump(10)
		t.eq(good, 2)
		sim.done()
	end)

	-- 2. The call graph ------------------------------------------------------

	local function walk(dir, out)
		for _, entry in ipairs(fs.readDir(dir)) do
			local path = dir .. "/" .. entry
			if fs.isDir(path) then
				walk(path, out)
			elseif string.match(entry, "%.luau$") then
				out[path] = fs.readFile(path)
			end
		end
	end
	local sources = {}
	walk("src", sources)

	-- Comments say "CreateMeshPartAsync" and "MeshKit.Preload" all over; only
	-- code counts.
	local function code(text)
		return (string.gsub(text, "%-%-[^\n]*", ""))
	end
	local codeOf = {}
	for path, text in pairs(sources) do
		codeOf[path] = code(text)
	end

	local function filesWith(pattern, plain)
		local hits = {}
		for path, text in pairs(codeOf) do
			if string.find(text, pattern, 1, plain) then
				table.insert(hits, path)
			end
		end
		table.sort(hits)
		return hits
	end

	local MESHKIT = "src/ReplicatedStorage/Shared/Art/MeshKit.luau"

	t.test("call graph: only MeshKit asks the engine for a mesh", function()
		t.eq(filesWith(":CreateMeshPartAsync(", true), { MESHKIT }, "the one engine call")
		-- T420: the stump frustums are uploaded as Model assets and loaded by the
		-- server at runtime, in the background, after the build (StumpMeshes
		-- preloads them from SectionTrees.Init). That one loader is the only
		-- allowed InsertService user; nothing on the map build path may be.
		t.eq(
			filesWith("InsertService", true),
			{ "src/ServerScriptService/StumpMeshes.luau" },
			"no model downloads on the build path (the stump loader is the one runtime exception)"
		)
		for path, text in pairs(codeOf) do
			if string.find(path, "ServerScriptService", 1, true) then
				t.ok(not string.find(text, "ContentProvider", 1, true), path .. " waits on ContentProvider")
			end
		end
	end)

	t.test("call graph: the yielding calls are fenced to background threads", function()
		-- CreateAwait yields. Only ItemMeshes.LoadAsync (PlotService.Init spawns it
		-- on its own thread) may call it.
		t.eq(filesWith("CreateAwait(", true), { MESHKIT, "src/ReplicatedStorage/Shared/ItemMeshes.luau" })
		-- The blocking join. MeshKit.PreloadAsync is the start path's call. DealershipLot.Preload
		-- is the other: the lot is a deferred queue step on its own thread (MapBuilder defers it),
		-- and it joins the vehicle meshes so a display truck is meshed before it is fitted and
		-- prepped (T390; a late swap onto a fitted copy would float).
		t.eq(filesWith("MeshKit.Preload(", true), {
			"src/ReplicatedStorage/Shared/Art/DealershipLot.luau",
			MESHKIT,
			"src/ReplicatedStorage/Shared/ItemMeshes.luau",
		})
		local itemMeshes = sources["src/ReplicatedStorage/Shared/ItemMeshes.luau"]
		t.ok(string.find(itemMeshes, "function ItemMeshes.LoadAsync", 1, true))
		t.eq(
			filesWith("ItemMeshes.LoadAsync()", true),
			{ "src/ReplicatedStorage/Shared/ItemMeshes.luau", "src/ServerScriptService/PlotService.luau" },
			"the definition and the one caller"
		)
		local plots = sources["src/ServerScriptService/PlotService.luau"]
		t.ok(
			string.find(plots, "task.spawn%(function%(%)%s*ItemMeshes.LoadAsync%(%)") ~= nil
				or string.find(plots, "spawn%(function%(%)%s*ItemMeshes.LoadAsync%(%)") ~= nil,
			"PlotService runs LoadAsync on its own thread"
		)
	end)

	t.test("call graph: the world build and the services never wait on a mesh", function()
		local build = codeOf["src/ServerScriptService/MapBuilder.server.luau"]
		t.ok(not string.find(build, "MeshKit.Create", 1, true), "MapBuilder asks for no mesh itself")
		t.ok(not string.find(build, "MeshKit.Preload(", 1, true), "MapBuilder does not join a preload")
		t.ok(string.find(build, "MeshKit.PreloadAsync(", 1, true), "it starts the preload on its own thread")
		t.ok(not string.find(build, 'Gates.Wait("meshes"', 1, true))
		t.ok(not string.find(build, 'WaitAll({ "meshes"', 1, true))
		local npc = codeOf["src/ServerScriptService/NPCService.luau"]
		t.ok(not string.find(npc, "MeshKit.Preload(", 1, true), "NPCService does not join a preload")
		t.ok(string.find(npc, "MeshKit.PreloadAsync(", 1, true))
		local plot = codeOf["src/ServerScriptService/PlotService.luau"]
		t.ok(not string.find(plot, 'gates.Wait("itemMeshes"', 1, true), "PlotService.Init does not wait for the kit")
		for path, text in pairs(codeOf) do
			if string.find(path, "ServerScriptService", 1, true) then
				t.ok(not string.find(text, 'Wait("meshes"', 1, true), path .. " waits on the meshes gate")
				t.ok(not string.find(text, 'Wait("itemMeshes"', 1, true), path .. " waits on the item meshes gate")
			end
		end
		local JoinFlow = t.shared("JoinFlow")
		for _, gate in ipairs(JoinFlow.FirstPlayerGates) do
			t.ok(gate ~= "meshes" and gate ~= "itemMeshes", "a player is not held for gate " .. gate)
		end
	end)

	t.test("call graph: every dresser that creates a mesh runs inside MeshKit.Attempt", function()
		-- A dresser that calls Create outside an Attempt keeps its part-built
		-- art for good if the mesh is late. MachineSkin.Prepare only loads the
		-- pieces; LogicItems.applyMeshes is the Attempt around it.
		local exempt = {
			[MESHKIT] = true,
			["src/ReplicatedStorage/Shared/Art/MachineSkin.luau"] = "LogicItems",
			["src/ReplicatedStorage/Shared/ItemMeshes.luau"] = "CreateAwait",
		}
		local callers = filesWith("MeshKit.Create(", true)
		t.ok(#callers >= 10, "found the dressers (" .. #callers .. ")")
		for _, path in ipairs(callers) do
			if not exempt[path] then
				t.ok(
					string.find(codeOf[path], "MeshKit.Attempt(", 1, true) ~= nil,
					path .. " calls MeshKit.Create without MeshKit.Attempt (no swap when the mesh lands)"
				)
			end
		end
		t.ok(string.find(sources["src/ReplicatedStorage/Shared/LogicItems.luau"], "MeshKit.Attempt(", 1, true))
		t.ok(not string.find(sources["src/ReplicatedStorage/Shared/ItemMeshes.luau"], "MeshKit.Create(", 1, true))
	end)

	t.test("call graph: every real dresser entry point goes through Attempt", function()
		local entries = {
			{
				"src/ReplicatedStorage/Shared/Art/TownMeshes.luau",
				"function TownMeshes.Dress",
				"MeshKit.Attempt(model",
			},
			{
				"src/ReplicatedStorage/Shared/Art/TownMeshes.luau",
				"function TownMeshes.Adorn",
				"MeshKit.Attempt(parent",
			},
			{ "src/ReplicatedStorage/Shared/Art/NPCMeshes.luau", "function NPCMeshes.Dress", "MeshKit.Attempt(model" },
			{
				"src/ReplicatedStorage/Shared/Art/VehicleMeshes.luau",
				"function VehicleMeshes.Apply",
				"MeshKit.Attempt(model",
			},
			{
				"src/ReplicatedStorage/Shared/Art/TreeMeshes.luau",
				"function TreeMeshes.Apply",
				"MeshKit.Attempt(model",
			},
			{ "src/ReplicatedStorage/Shared/KitMeshes.luau", "function KitMeshes.Dress", "MeshKit.Attempt(model" },
			{
				"src/ReplicatedStorage/Shared/Art/RobuxBoxArt.luau",
				"function RobuxBoxArt.Dress",
				"MeshKit.Attempt(parent",
			},
		}
		for _, entry in ipairs(entries) do
			local text = sources[entry[1]]
			local at = string.find(text, entry[2], 1, true)
			t.ok(at, entry[2] .. " exists")
			local body = string.sub(text, at, at + 900)
			t.ok(string.find(body, entry[3], 1, true), entry[2] .. " does not go through MeshKit.Attempt")
		end
	end)

	t.test("client: the loading card and the client never wait for the meshes", function()
		local card = codeOf["src/ReplicatedFirst/LoadingScreen.client.luau"]
		local readyAt = string.find(card, "local function ready()", 1, true)
		t.ok(readyAt, "found the card's ready check")
		local readyBody = string.sub(card, readyAt, readyAt + 400)
		t.ok(not string.find(readyBody, "Mesh", 1, true), "ready() does not look at meshes")
		t.ok(not string.find(readyBody, "ContentProvider", 1, true), "ready() does not wait on ContentProvider")
		t.ok(not string.find(card, "ContentProvider", 1, true), "the card never preloads assets")
		t.ok(not string.find(card, "MeshKit", 1, true))
		t.eq(tonumber(string.match(card, "MAX_SECONDS = (%d+)")), 30, "the card gives up after 30 s whatever happens")
		-- The one client preload (UI images) runs on its own thread.
		local clientPreloads = {}
		for path, text in pairs(codeOf) do
			if string.find(path, "StarterPlayer", 1, true) and string.find(text, "PreloadAsync", 1, true) then
				table.insert(clientPreloads, path)
			end
		end
		t.eq(clientPreloads, { "src/StarterPlayer/StarterPlayerScripts/UIArt.luau" })
		t.ok(string.find(codeOf[clientPreloads[1]], "later%(function%(%)%s*local ContentProvider") ~= nil)
		-- Client dressers are the same non-blocking MeshKit: AmbientLife builds
		-- rocks and mushrooms through NatureArt on the client's render thread.
		t.eq(filesWith("MeshKit.CreateAwait(", true), { MESHKIT, "src/ReplicatedStorage/Shared/ItemMeshes.luau" })
		for path in pairs(codeOf) do
			if string.find(path, "StarterPlayer", 1, true) then
				t.ok(not string.find(codeOf[path], "MeshKit.Preload(", 1, true), path .. " joins a preload")
			end
		end
	end)

	-- 3. The timing report and the budget -------------------------------------

	t.test("BuildTimings: gating steps add up against the 15 s play budget", function()
		local BuildTimings = t.shared("BuildTimings")
		t.eq(BuildTimings.PlayBudgetSeconds, 15)
		local timings = BuildTimings.new()
		timings.Record("3. Terrain", 2.4, true)
		timings.Record("4. The shops", 0.8, true)
		timings.Record("5. The country", 40, false) -- deferred: after play starts
		t.eq(#timings.Steps(), 3)
		t.ok(math.abs(timings.GatingSeconds() - 3.2) < 1e-9)
		t.eq(timings.OverBudget(), false)
		t.eq(timings.Slowest().name, "3. Terrain")
		local lines = timings.Lines()
		t.eq(#lines, 3, "two gating steps and the total (the deferred step is not counted)")
		t.ok(string.find(lines[#lines], "ok", 1, true))
		-- Connor's 12 October log: the shops alone took 300.2 s.
		timings.Record("4. The shops (the 12 October build)", 300.2, true)
		t.eq(timings.OverBudget(), true)
		t.eq(timings.Slowest().name, "4. The shops (the 12 October build)")
		local last = timings.Lines()
		t.ok(string.find(last[#last], "OVER BUDGET", 1, true))
		local slow = false
		for _, line in ipairs(last) do
			if string.find(line, "<-- slow", 1, true) then
				slow = true
			end
		end
		t.ok(slow, "the slow step is flagged")
		t.eq(BuildTimings.new().GatingSeconds(), 0)
		local junk = BuildTimings.new()
		junk.Record("x", 0 / 0, true)
		junk.Record("y", -5, true)
		t.eq(junk.GatingSeconds(), 0, "a bad number is 0, never an error")
	end)

	t.test("MapBuilder records every top-level step and prints the report at the world gate", function()
		local build = sources["src/ServerScriptService/MapBuilder.server.luau"]
		t.ok(string.find(build, "buildTimings.Record(name", 1, true), "step() records its seconds")
		t.ok(string.find(build, "buildTimings.Lines()", 1, true), "the report is printed")
		t.ok(string.find(build, "buildTimings.OverBudget()", 1, true), "an over-budget build is warned")
	end)

	t.test(
		"the manifest is the 685 meshes of the 12 October log plus the store gear and the worn gear (town meshes off)",
		function()
			local MeshManifest = t.shared("Art/MeshManifest")
			-- 685 + 5: the store item model slots (StoreModelSlots, group "store") preload the gear's
			-- ids (InsulatedCoat 1, HeatBoots 2, FeatherfallCloak 2); the lamp post's two are already
			-- in the "items" group. +6: the baked store models (Barrel, Crate, GlowWire, SkyBin,
			-- RobuxCoins, Parcel; 13 Oct upload). +14: the worn gear (WornModels, group "worn": coat,
			-- sleeve, boots, cloak, hardhat, belt, ladder tiles, scroll V2; 16 Oct upload). +12:
			-- Cherry and Willow (TreeModels: 3 sections and 3 crowns each; WORLD-T323).
			-- +10: the Sky Forge Court (5 visual pieces and its collision hull) and the Starfall
			-- Forge (3 and its hull), dressed by BuildingArt (T381).
			t.eq(#MeshManifest.Flat(false), 732, "732 ids start loading in the background; none is awaited")
		end
	)
end
