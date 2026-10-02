--!nocheck
-- ForestFiller (StarterPlayerScripts/ForestFiller, FOR-02), the real module
-- run frame by frame against a fake workspace, camera, Heartbeat and clock:
--   * it builds exactly WorldPlan's plan round the camera (the trees within
--     FillerNear, the stand-ins out to FillerFar), every part decoration
--     (anchored, no collisions, clicks or touches, no shadow), in the
--     workspace folder ForestFiller;
--   * it spreads the work: a few cells a frame inside FillerBuildMs;
--   * moving the camera swaps cells in and out, with no cell built twice;
--   * a crown between the camera and its focus fades, and comes back.
return function(t)
	local roblox = t.roblox
	local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
	local QualityBudgets = t.shared("QualityBudgets")

	local function world(tier)
		local w = { clock = 0, heartbeat = {}, tier = tier or "high", builtPerFrame = 0 }
		w.workspace = Instance.new("Workspace")
		w.camera = Instance.new("Camera")
		w.camera.Parent = w.workspace
		w.workspace.CurrentCamera = w.camera
		local loader = t.loader({
			services = {
				RunService = {
					Heartbeat = {
						Connect = function(_, fn)
							table.insert(w.heartbeat, fn)
						end,
					},
				},
			},
			mocks = {
				Quality = {
					Budget = function()
						return QualityBudgets.For(w.tier)
					end,
				},
			},
			globals = {
				workspace = w.workspace,
				task = {
					spawn = function(fn, ...)
						fn(...)
					end,
					wait = function() end,
				},
				print = function() end,
				os = {
					-- Every reading moves the clock on 0.4 ms (about what building a
					-- cell of trees costs), so a frame's build budget is a fixed amount of work.
					clock = function()
						w.clock += 0.0004
						return w.clock
					end,
				},
			},
		})
		w.loader = loader
		w.ForestFiller = loader:load("StarterPlayer/StarterPlayerScripts/ForestFiller")
		w.WorldPlan = loader:load("ReplicatedStorage/Shared/World/WorldPlan")
		w.PropArt = loader:load("ReplicatedStorage/Shared/Art/PropArt")
		function w.look(at, focus)
			w.camera.CFrame = CFrame.new(at)
			w.camera.Focus = CFrame.new(focus or at + Vector3.new(0, 0, -12))
		end
		function w.frame()
			for _, fn in ipairs(w.heartbeat) do
				fn(1 / 60)
			end
		end
		-- Frames until nothing changes for a while (or `most` frames).
		function w.settle(most)
			local folder = w.workspace:FindFirstChild("ForestFiller")
			local last, still = -1, 0
			for f = 1, most do
				w.frame()
				folder = folder or w.workspace:FindFirstChild("ForestFiller")
				local n = if folder then #folder:GetChildren() else 0
				if n == last then
					still += 1
					if still > 40 then
						return f
					end
				else
					still = 0
				end
				last = n
			end
			return most
		end
		function w.folder()
			return w.workspace:FindFirstChild("ForestFiller")
		end
		return w
	end

	-- What WorldPlan says a camera at `at` should show: parts per cell key.
	local function expected(w, at)
		local budget = QualityBudgets.For(w.tier)
		local partsOf = {}
		for _, kind in ipairs(w.PropArt.FillerKinds) do
			partsOf[kind] = {}
			for v = 1, w.PropArt.FillerVariants do
				local n = 0
				for _, d in ipairs(w.PropArt.FillerTree(kind, v):GetDescendants()) do
					n += if d:IsA("BasePart") then 1 else 0
				end
				partsOf[kind][v] = n
			end
		end
		local plan = w.WorldPlan.FillerPlanAround(at.X, at.Y, at.Z, budget.FillerNear, budget.FillerFar)
		local near, far = 0, 0
		for key, mode in pairs(plan) do
			local cx, cz = w.WorldPlan.FillerCellOf(key)
			if mode == "near" then
				for _, tree in ipairs(w.WorldPlan.FillerCellTrees(cx, cz)) do
					near += partsOf[tree.kind][tree.variant]
				end
			else
				far += #w.WorldPlan.FillerFarCell(cx, cz)
			end
		end
		return near, far
	end

	-- A part's LocalTransparencyModifier (Lune has no default for it: unset is 0).
	local function ltm(p)
		local ok, v = pcall(function()
			return p.LocalTransparencyModifier
		end)
		return if ok then v else 0
	end

	local function count(folder)
		local near, far, bad = 0, 0, {}
		local names = {}
		for _, cell in ipairs(folder:GetChildren()) do
			t.ok(not names[cell.Name], "cell " .. cell.Name .. " built twice")
			names[cell.Name] = true
			for _, p in ipairs(cell:GetChildren()) do
				if p:IsA("BasePart") then
					if string.sub(cell.Name, 1, 4) == "near" then
						near += 1
					else
						far += 1
					end
					if not p.Anchored or p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow then
						table.insert(bad, cell.Name .. "/" .. p.Name)
					end
				end
			end
		end
		return near, far, bad
	end

	t.test("it builds exactly the plan round the camera, all of it decoration", function()
		for _, tier in ipairs({ "high", "low" }) do
			local w = world(tier)
			local at = Vector3.new(-100, 8, -450) -- deep in the south forest
			w.look(at)
			w.ForestFiller.Start()
			t.eq(#w.heartbeat, 1, "it steps on Heartbeat")
			local frames = w.settle(4000)
			t.ok(frames < 4000, tier .. ": it finishes loading")
			local folder = w.folder()
			t.ok(folder and folder:IsA("Folder"), "the ForestFiller folder")
			local near, far, bad = count(folder)
			local wantNear, wantFar = expected(w, at)
			t.eq(near, wantNear, tier .. ": filler parts")
			t.eq(far, wantFar, tier .. ": stand-in parts")
			t.ok(near > 1000, tier .. ": " .. near .. " filler parts round you")
			t.eq(#bad, 0, "parts that aren't decoration: " .. table.concat(bad, ", "))
		end
	end)

	t.test("it spreads the work over frames, nearest cells first", function()
		local w = world("high")
		local at = Vector3.new(-100, 8, -450)
		w.look(at)
		w.ForestFiller.Start()
		local seen, firstFar = 0, nil
		local nearestFirst = true
		local lastD = -1
		for f = 1, 30 do
			w.frame()
			local folder = w.folder()
			local cells = if folder then folder:GetChildren() else {}
			t.ok(#cells - seen <= 6, string.format("frame %d built %d cells", f, #cells - seen))
			for i = seen + 1, #cells do
				local mode, cx, cz = string.match(cells[i].Name, "^(%a+) (%-?%d+) (%-?%d+)$")
				if mode == "far" then
					firstFar = firstFar or f
				end
				local d = Vector3.new((tonumber(cx) + 0.5) * 32 - at.X, 0, (tonumber(cz) + 0.5) * 32 - at.Z).Magnitude
				if mode == "near" then
					nearestFirst = nearestFirst and d >= lastD - 46 -- (cells, not points: a cell's width)
					lastD = math.max(lastD, d)
				end
			end
			seen = #cells
		end
		t.ok(seen > 30, seen .. " cells in 30 frames")
		t.ok(nearestFirst, "the nearest trees come first")
		t.eq(firstFar, nil, "no stand-in before the trees round you")
	end)

	t.test("moving the camera swaps cells in and out; the totals follow it", function()
		local w = world("low")
		w.look(Vector3.new(-100, 8, -450))
		w.ForestFiller.Start()
		w.settle(4000)
		local to = Vector3.new(200, 8, 500) -- the north forest
		w.look(to)
		w.settle(4000)
		local near, far = count(w.folder())
		local wantNear, wantFar = expected(w, to)
		-- (Cells a hysteresis-width past the radii may linger: they're from
		-- the walk, not the plan; at 950 studs away, none of the old ones.)
		t.eq(near, wantNear, "the trees round the new spot")
		t.eq(far, wantFar, "the stand-ins round the new spot")
	end)

	t.test("a crown between the camera and its focus fades, and comes back", function()
		local w = world("high")
		local at = Vector3.new(-100, 8, -450)
		w.look(at)
		w.ForestFiller.Start()
		w.settle(4000)
		-- A filler tree near the camera: look through its crown at a spot behind it.
		local tree
		for cx = -5, -3 do
			for cz = -16, -13 do
				for _, spot in ipairs(w.WorldPlan.FillerCellTrees(cx, cz)) do
					tree = tree or spot
				end
			end
		end
		t.ok(tree ~= nil, "a filler tree to look through")
		local crownY = tree.y + 13
		local eye = Vector3.new(tree.x - 10, crownY, tree.z)
		local focus = Vector3.new(tree.x + 10, crownY, tree.z)
		w.look(eye, focus)
		for _ = 1, 12 do
			w.frame()
		end
		local faded = 0
		for _, cell in ipairs(w.folder():GetChildren()) do
			for _, p in ipairs(cell:GetChildren()) do
				if ltm(p) > 0 then
					faded += 1
					t.ok(p.Name ~= "FillerTrunk", "only crowns fade")
					t.eq(ltm(p), 0.75)
				end
			end
		end
		t.ok(faded >= 1, "the crown in the way fades")
		w.look(at + Vector3.new(0, 300, 0), at + Vector3.new(0, 288, 0)) -- up and away
		for _ = 1, 12 do
			w.frame()
		end
		local still = 0
		for _, cell in ipairs(w.folder():GetChildren()) do
			for _, p in ipairs(cell:GetChildren()) do
				still += if ltm(p) > 0 then 1 else 0
			end
		end
		t.eq(still, 0, "and comes back once it's out of the way")
	end)
end
