--!nocheck
-- Mesh swap-ins in bursts (Studio, 14 October 2026: 696 of them landing while
-- the world was still building, each frame's worth a hitch). Every swap-in
-- (MeshKit.Attempt: the shops, boxes, vehicles, machines, NPCs, trees...) goes
-- through ONE per-frame drain: at most MeshKit.SwapMaxPerFrame swaps, inside
-- the time budget and the shared frame budget, nearest the players first.
-- The part-first contract is unchanged: a mesh that lands later still swaps
-- in, an unset or failed id changes nothing (BuildBudget.spec, MachineSwap.spec).
return function(t)
	local roblox = t.roblox
	local SIZE = roblox.Vector3.new(1, 1, 1)

	-- MeshKit with a held engine (as in BuildBudget.spec) and a fake clock that
	-- moves 0.1 ms per read.
	local function kit()
		local loader = t.loader()
		local MeshKit = loader:shared("Art/MeshKit")
		MeshKit.Reset()
		MeshKit.Override = nil
		MeshKit.Retries = 0
		MeshKit.Focus = nil
		MeshKit.SwapFrame = nil
		local jobs, frames = {}, { count = 0 }
		local clockNow = 0
		local sim = { pumps = {}, order = {} }
		local realPump = MeshKit.Pump
		MeshKit.Pump = function(budget)
			if sim.hold then
				error("held") -- the drain thread started by the first landing: kept out of the way
			end
			local ran = realPump(budget)
			table.insert(sim.pumps, ran)
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
				clockNow += 0.0001
				return clockNow
			end,
		}
		MeshKit.EngineLoad = function(meshId)
			local part = roblox.Instance.new("MeshPart")
			part.Name = "Loaded" .. tostring(meshId)
			return part, nil
		end
		function sim.runJobs()
			while #jobs > 0 do
				pcall(table.remove(jobs, 1))
			end
		end
		sim.frames = frames
		return MeshKit, sim
	end

	-- `count` dressings, each at its own place, waiting on its own mesh; every
	-- mesh has landed (so they are all ready), none has been swapped yet.
	local function ready(MeshKit, sim, count, where, drain)
		local holder = roblox.Instance.new("Model")
		local models = {}
		for id = 1, count do
			local model = roblox.Instance.new("Model")
			model.Parent = holder
			model:PivotTo(roblox.CFrame.new(where(id), 0, 0))
			models[id] = model
			MeshKit.Attempt(model, function()
				local part = MeshKit.Create(id, "Piece", SIZE)
				if not part then
					return false
				end
				part.Parent = model
				table.insert(sim.order, id)
				return true
			end)
		end
		-- The meshes land: every dressing is ready. The drain thread is held (it
		-- would swap them all inside this call) unless the test wants it.
		sim.hold = not drain
		sim.runJobs()
		sim.hold = false
		return models
	end

	t.test("a frame swaps at most SwapMaxPerFrame, however many are ready and however cheap", function()
		local MeshKit, sim = kit()
		MeshKit.SwapBudget = 1 -- the time never limits: only the cap does
		t.eq(MeshKit.SwapMaxPerFrame, 6)
		ready(MeshKit, sim, 100, function(id)
			return id
		end)
		t.eq(MeshKit.SwapStats().ready, 100)
		local total = 0
		sim.pumps = {}
		-- The drain thread: one Pump a frame.
		while MeshKit.SwapStats().ready > 0 do
			local ran = MeshKit.Pump()
			t.ok(ran <= 6, "a frame swapped " .. ran)
			total += ran
		end
		t.eq(total, 100, "every dressing ran exactly once")
		t.eq(#sim.order, 100)
		t.eq(MeshKit.SwapStats().swapped, 100)
		t.ok(#sim.pumps >= 17, #sim.pumps .. " frames for 100 swaps")
	end)

	t.test("the drain thread gives a frame back between batches", function()
		local MeshKit, sim = kit()
		MeshKit.SwapBudget = 1
		ready(MeshKit, sim, 30, function(id)
			return id
		end, true) -- the drain thread runs: one Pump a frame
		t.eq(MeshKit.SwapStats().ready, 0)
		for _, ran in ipairs(sim.pumps) do
			t.ok(ran <= 6, "a frame swapped " .. ran)
		end
		t.ok(sim.frames.count >= 2, "the drain waited for a frame between batches: " .. sim.frames.count)
	end)

	t.test("an explicit Pump budget is the caller's own: no cap (the specs, the swap on demand)", function()
		local MeshKit, sim = kit()
		ready(MeshKit, sim, 40, function(id)
			return id
		end)
		t.eq(MeshKit.Pump(10), 40)
	end)

	t.test("nearest the players first, whatever order the meshes landed in", function()
		local MeshKit, sim = kit()
		MeshKit.SwapBudget = 1
		-- Models along a line; the player stands at x = 80.
		MeshKit.Focus = function()
			return { { x = 80, z = 0 } }
		end
		ready(MeshKit, sim, 30, function(id)
			return id * 10
		end)
		MeshKit.Pump() -- one frame: the six nearest
		t.eq(#sim.order, 6)
		local firstFrame = table.clone(sim.order)
		table.sort(firstFrame)
		-- x = 80 is id 8; ids 5..11 are within 30 studs: the six nearest are 8, 7 or 9, ...
		t.eq(sim.order[1], 8, "the one the player stands at goes first")
		for _, id in ipairs(sim.order) do
			t.ok(math.abs(id * 10 - 80) <= 30, "id " .. id .. " is one of the six nearest")
		end
		-- Then the player runs to the far end: the rest follow them.
		MeshKit.Focus = function()
			return { { x = 300, z = 0 } }
		end
		MeshKit.Pump()
		t.eq(sim.order[7], 30, "the swap nearest the player's new place")
		-- All of them come out in the end.
		while MeshKit.SwapStats().ready > 0 do
			MeshKit.Pump()
		end
		t.eq(#sim.order, 30)
		local seen = {}
		for _, id in ipairs(sim.order) do
			t.eq(seen[id], nil, "swapped once")
			seen[id] = true
		end
	end)

	t.test("with nobody to measure from, the order they became ready in", function()
		local MeshKit, sim = kit()
		MeshKit.SwapBudget = 1
		MeshKit.Focus = function()
			return {}
		end
		ready(MeshKit, sim, 12, function(id)
			return 1000 - id
		end)
		while MeshKit.SwapStats().ready > 0 do
			MeshKit.Pump()
		end
		local expected = {}
		for id = 1, 12 do
			table.insert(expected, id)
		end
		t.eq(sim.order, expected)
	end)

	t.test("the shared frame budget stops a frame's swaps once it is spent, but one always runs", function()
		local MeshKit, sim = kit()
		MeshKit.SwapBudget = 1
		local asked = 0
		local spentAfter = 2
		MeshKit.SwapFrame = {
			Over = function()
				asked += 1
				return asked % spentAfter == 0 -- spent after every second swap
			end,
		}
		ready(MeshKit, sim, 10, function(id)
			return id
		end)
		local ran = MeshKit.Pump()
		t.eq(ran, 2, "the frame's budget was spent after two")
		spentAfter = 1 -- already spent when the drain wakes
		t.eq(MeshKit.Pump(), 1, "a swap always runs, so the queue never stalls")
		spentAfter = 1000
		MeshKit.SwapFrame = nil
		while MeshKit.SwapStats().ready > 0 do
			MeshKit.Pump()
		end
		t.eq(#sim.order, 10)
	end)

	t.test("part-first is unchanged: an unset or failed mesh changes nothing, and a late one still swaps in", function()
		local MeshKit, sim = kit()
		local models = roblox.Instance.new("Model")
		local function dress(id)
			local model = roblox.Instance.new("Model")
			model.Parent = models
			local result = MeshKit.Attempt(model, function()
				local part = MeshKit.Create(id, "Piece", SIZE)
				if not part then
					return false
				end
				part.Parent = model
				return true
			end)
			return model, result
		end
		local zero, zeroResult = dress(0) -- an unset id: never loads
		t.eq(zeroResult, false)
		local late, lateResult = dress(77)
		t.eq(lateResult, false, "part-built for now")
		t.eq(late:FindFirstChildWhichIsA("MeshPart"), nil)
		sim.runJobs()
		while MeshKit.SwapStats().ready > 0 do
			MeshKit.Pump()
		end
		t.ok(late:FindFirstChildWhichIsA("MeshPart"), "the mesh that landed later swapped in")
		t.eq(zero:FindFirstChildWhichIsA("MeshPart"), nil, "an unset id changed nothing")
	end)
end
