--!nocheck
-- RegionWake (server audit leftover, 11 October 2026): the pass over every
-- tree ran whole every 0.75 s (GetAttribute x2, GetPivot and a region lookup
-- per person per tree for ~1,400 trees), and a tree planted into the forest
-- stayed in the workspace, replicated, until the next pass parked it. Now a
-- sweep is sliced (Batch trees a frame), skipped while the people stand
-- where the last finished sweep saw them, looks each person's region up once,
-- and parks a new tree the frame it arrives. These pin that the decisions
-- are the old ones, and the work.
return function(t)
	local Vector3 = t.roblox.Vector3
	local RegionLogic = t.load("ReplicatedStorage/Shared/RegionLogic")

	local function stream(seed)
		local state = seed
		return function()
			state = (state * 1103515245 + 12345) % 2147483648
			return state / 2147483648
		end
	end

	local function signal()
		return {
			Connect = function(self, fn)
				self.fn = fn
				return { Disconnect = function() end }
			end,
		}
	end

	local REGIONS = { "wild", "wild", "wild", "starter", "reach", "sky", "bayou", "canyon", "frost" }

	-- Everything the module touches, with counters.
	local function world(treeCount, seed)
		local w = { pivots = 0, attrs = 0, reparents = 0, regionLookups = 0, deferred = {} }
		local rand = stream(seed)
		local home = { Name = "Trees", children = {}, ChildAdded = signal() }
		function home.GetChildren(self)
			return self.children
		end
		function home.IsA()
			return true
		end
		local away = { Name = "AsleepRegions" }
		w.home, w.away = home, away
		local function newModel(i, x, y, z, region, tutorial)
			local store = { Parent = nil }
			local model
			model = setmetatable({
				Destroying = signal(),
				IsA = function(_, kind)
					return kind == "Model"
				end,
				GetAttribute = function(_, name)
					w.attrs += 1
					if name == "TutorialGrove" then
						return if tutorial then true else nil
					elseif name == "Region" then
						return region
					end
					return nil
				end,
				GetPivot = function()
					w.pivots += 1
					return { Position = Vector3.new(x, y, z) }
				end,
				id = i,
				at = Vector3.new(x, y, z),
				region = region,
				tutorial = tutorial,
			}, {
				__index = store,
				__newindex = function(_, key, value)
					if key == "Parent" then
						w.reparents += 1
					end
					store[key] = value
				end,
			})
			rawset(model, "dummy", nil)
			return model
		end
		w.newModel = newModel
		w.models = {}
		for i = 1, treeCount do
			local region = REGIONS[math.floor(rand() * #REGIONS) + 1]
			local y = if region == "sky" then 600 + rand() * 50 else rand() * 30
			local m = newModel(i, rand() * 2200 - 1100, y, rand() * 2200 - 1100, region, i % 97 == 0)
			m.Parent = home
			table.insert(home.children, m)
			table.insert(w.models, m)
		end
		w.reparents = 0
		w.people = {}
		w.heartbeat = nil
		local players = {
			GetPlayers = function()
				local out = {}
				for _, at in ipairs(w.people) do
					table.insert(out, {
						Character = {
							FindFirstChild = function()
								return { Position = at }
							end,
						},
					})
				end
				return out
			end,
		}
		local loader = t.loader({
			services = {
				Players = players,
				RunService = { Heartbeat = { Connect = function() end } },
				ServerStorage = {},
			},
			globals = {
				Instance = {
					new = function()
						return away
					end,
				},
				task = {
					spawn = function(fn)
						fn()
					end,
					defer = function(fn)
						table.insert(w.deferred, fn)
					end,
				},
			},
		})
		w.RegionWake = loader:server("RegionWake")
		w.RegionWake.Attach(home)
		function w.flush()
			local list = w.deferred
			w.deferred = {}
			for _, fn in ipairs(list) do
				fn()
			end
		end
		-- Frames until the sweep started by the next tick is done.
		function w.sweep()
			local frames = 0
			w.RegionWake.Step(w.RegionWake.Tick) -- the tick
			frames += 1
			while frames < 100 do
				local before = w.pivots
				w.RegionWake.Step(1 / 60)
				if w.pivots == before then
					break
				end
				frames += 1
			end
			return frames
		end
		return w
	end

	-- What the old pass decided for each tree.
	local function oldWant(m, list)
		if m.tutorial then
			return "home"
		end
		local keep = RegionLogic.KeepTree(m.region or "wild", m.at.X, m.at.Z, m.at.Y, list)
		return if keep then "home" else "away"
	end
	local function personsFrom(points)
		local list = {}
		for _, p in ipairs(points) do
			table.insert(list, { x = p.X, z = p.Z, y = p.Y })
		end
		return list
	end

	t.test("KeepTreeWith(Heres) answers what KeepTree answers", function()
		local rand = stream(4)
		for _ = 1, 3000 do
			local people = {}
			for _ = 1, 1 + math.floor(rand() * 3) do
				table.insert(people, { x = rand() * 2200 - 1100, z = rand() * 2200 - 1100, y = rand() * 700 })
			end
			local region = REGIONS[math.floor(rand() * #REGIONS) + 1]
			local x, z, y = rand() * 2200 - 1100, rand() * 2200 - 1100, rand() * 700
			t.eq(
				RegionLogic.KeepTreeWith(region, x, z, y, people, RegionLogic.Heres(people)),
				RegionLogic.KeepTree(region, x, z, y, people)
			)
		end
	end)

	t.test("a sweep parks and wakes exactly the trees the old pass did", function()
		for _, spots in ipairs({
			{ Vector3.new(0, 6, 40) },
			{ Vector3.new(-600, 6, 440), Vector3.new(700, 8, -500) },
			{ Vector3.new(30, 650, 30) },
		}) do
			local w = world(1400, 17)
			w.people = spots
			w.sweep()
			local list = personsFrom(spots)
			for _, m in ipairs(w.models) do
				local parent = rawget(m, "Parent") or m.Parent
				local want = oldWant(m, list)
				t.eq(if parent == w.home then "home" else "away", want, "tree " .. m.id)
			end
		end
	end)

	t.test("a sweep is sliced, Batch trees a frame, and the people standing still cost nothing", function()
		local w = world(1400, 5)
		w.people = { Vector3.new(0, 6, 40) }
		local mostPivots = 0
		w.RegionWake.Step(w.RegionWake.Tick)
		mostPivots = w.pivots
		local frames = 1
		while true do
			local before = w.pivots
			w.RegionWake.Step(1 / 60)
			mostPivots = math.max(mostPivots, w.pivots - before)
			if w.pivots == before then
				break
			end
			frames += 1
		end
		print(
			string.format(
				"RegionWake: 1400 trees swept in %d frames, at most %d trees a frame (was 1400 in one)",
				frames,
				mostPivots
			)
		)
		t.ok(mostPivots <= w.RegionWake.Batch, "slice " .. mostPivots)
		t.ok(frames >= 1400 / w.RegionWake.Batch)
		-- Same people, many ticks: no tree is looked at.
		local pivots, attrs = w.pivots, w.attrs
		for _ = 1, 40 do
			w.RegionWake.Step(w.RegionWake.Tick)
		end
		t.eq({ w.pivots, w.attrs }, { pivots, attrs }, "idle: no work")
		-- Someone moves: a sweep again.
		w.people = { Vector3.new(500, 6, 40) }
		w.RegionWake.Step(w.RegionWake.Tick)
		t.ok(w.pivots > pivots, "moved: sweeping")
	end)

	t.test("a tree planted into the forest is put where it belongs the frame it arrives", function()
		local w = world(300, 9)
		w.people = { Vector3.new(0, 6, 40) }
		w.sweep()
		local far = w.newModel(9001, 900, 5, -900, "wild", false)
		far.Parent = w.home
		table.insert(w.home.children, far)
		w.reparents = 0
		w.home.ChildAdded.fn(far)
		w.flush() -- the beat the module waits for the placer's attributes
		t.ok(far.Parent == w.away, "a far tree is parked at once, before the next sweep")
		t.eq(w.reparents, 1)
		local near = w.newModel(9002, 20, 3, 60, "wild", false)
		near.Parent = w.home
		w.reparents = 0
		w.home.ChildAdded.fn(near)
		w.flush()
		t.ok(near.Parent == w.home)
		t.eq(w.reparents, 0, "a near tree is left alone")
	end)
end
